// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package agent

import (
	"archive/zip"
	"bufio"
	"bytes"
	"context"
	"crypto/md5"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/d-led/ex_gocd/agent/internal/config"
	agentlog "github.com/d-led/ex_gocd/agent/internal/log"
	"github.com/d-led/ex_gocd/agent/internal/registration"
	"github.com/d-led/ex_gocd/agent/internal/telemetry"
	"github.com/d-led/ex_gocd/agent/internal/websocket"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// ErrServerUnavailable indicates the GoCD server is unreachable (planned outage,
// network blip, etc.). Callers should not count this against crash restart limits.
var ErrServerUnavailable = errors.New("gocd server unavailable")

// Agent represents the GoCD agent
type Agent struct {
	config    *config.Config
	registrar *registration.Registrar
	conn      *websocket.Connection
	cookie    string
	state     string

	// Elastic agent idle timeout: when set (>0), agent self-terminates after idle this long.
	// idleSince is set when entering Idle state, cleared when building.
	idleSince time.Time

	// Heartbeat tracking: lastAck is updated on phx_reply. If the server stops
	// acknowledging pings, we log a warning (once per missed window).
	lastAck         time.Time
	missedAckLogged bool

	// Current build cancellation: guarded by buildMu
	buildMu       sync.Mutex
	currentBuild  string             // buildId of running build, or ""
	cancelBuildFn context.CancelFunc // call to cancel current build
}

// New creates a new Agent
func New(cfg *config.Config) (*Agent, error) {
	// UUID already resolved by main.go into AGENT_UUID env var
	cfg.UUID = os.Getenv("AGENT_UUID")
	if cfg.UUID == "" {
		return nil, fmt.Errorf("AGENT_UUID not set — main.go should have resolved it")
	}

	return &Agent{
		config:    cfg,
		registrar: registration.New(cfg),
		state:     "Idle",
		idleSince: time.Now(),
		lastAck:   time.Now(),
	}, nil
}

// Start runs the agent lifecycle with automatic reconnection:
// 1. Register with server
// 2. Connect WebSocket (with reconnection)
// 3. Send ping heartbeats
// 4. Process incoming messages
func (a *Agent) Start(ctx context.Context) error {
	// Startup span covers OTel init + registration.
	// No-op tracer is safe before telemetry.Setup() — returns a non-recording span.
	tracer := otel.Tracer("gocd-agent")
	startCtx, startupSpan := tracer.Start(ctx, "agent.start",
		trace.WithAttributes(
			attribute.String("agent.uuid", a.config.UUID),
			attribute.String("server.url", a.config.ServerURL.String()),
			attribute.String("agent.workdir", a.config.WorkingDir),
			attribute.String("agent.go_version", runtime.Version()),
		),
	)
	defer startupSpan.End()

	// Initialize OpenTelemetry (no-op when OTEL_TRACES_EXPORTER != "otlp")
	otelShutdown := telemetry.Setup()
	defer func() { _ = otelShutdown(context.Background()) }()

	// Start periodic runtime metrics (goroutines, memory, GC)
	stopMetrics := agentlog.StartRuntimeMetrics(startCtx, &agentlog.Logger, 30*time.Second)
	defer stopMetrics()

	agentlog.Logger.Info().Str("uuid", a.config.UUID).Str("server", a.config.ServerURL.String()).Str("workdir", a.config.WorkingDir).Str("go_version", runtime.Version()).Msg("agent starting")

	// Register with server
	agentlog.Logger.Info().Msg("Registering with server...")
	if err := a.registrar.Register(); err != nil {
		startupSpan.RecordError(err)
		startupSpan.SetStatus(codes.Error, "registration failed")
		return fmt.Errorf("%w: registration failed: %w", ErrServerUnavailable, err)
	}
	agentlog.Logger.Info().Msg("Registration successful")

	// Create TLS config for WebSocket
	tlsConfig, err := a.registrar.CreateTLSConfig()
	if err != nil {
		return fmt.Errorf("%w: failed to create TLS config: %w", ErrServerUnavailable, err)
	}

	// Main reconnection loop with exponential backoff.
	// Backoff resets after a stable connection (>= minStableConnection) so that
	// transient blips don't accumulate delay permanently.
	const baseRetryDelay = 2 * time.Second
	const maxRetryDelay = 60 * time.Second
	const minStableConnection = 30 * time.Second

	retryDelay := baseRetryDelay

	for {
		select {
		case <-ctx.Done():
			agentlog.Logger.Info().Msg("Agent shutting down...")
			return nil
		default:
		}

		// Try to connect and run
		connStart := time.Now()
		err := a.runWithConnection(ctx, tlsConfig)
		if err == nil {
			return nil // Clean shutdown
		}

		// Check if context was cancelled
		if ctx.Err() != nil {
			agentlog.Logger.Info().Msg("Agent shutting down...")
			return nil
		}

		// Reset backoff if the connection was stable for a while before dropping.
		// A long-lived connection that eventually drops is likely a transient blip,
		// not a persistent infrastructure problem.
		if time.Since(connStart) >= minStableConnection {
			agentlog.Logger.Info().Dur("uptime", time.Since(connStart).Round(time.Second)).Msg("Connection was stable, resetting reconnect backoff")
			retryDelay = baseRetryDelay
		}

		// Log error and retry with backoff
		agentlog.Logger.Info().Err(err).Msg("Connection lost")
		agentlog.Logger.Info().Dur("retry_delay", retryDelay).Msg("Reconnecting...")

		select {
		case <-time.After(retryDelay):
			// Exponential backoff with max
			retryDelay = retryDelay * 2
			if retryDelay > maxRetryDelay {
				retryDelay = maxRetryDelay
			}
		case <-ctx.Done():
			agentlog.Logger.Info().Msg("Agent shutting down...")
			return nil
		}
	}
}

// runWithConnection establishes WebSocket and runs until disconnection
func (a *Agent) runWithConnection(ctx context.Context, tlsConfig *tls.Config) error {
	tracer := otel.Tracer("gocd-agent")

	// Span covers WebSocket dial + join (not heartbeats)
	hsCtx, hsSpan := tracer.Start(ctx, "agent.handshake",
		trace.WithAttributes(
			attribute.String("agent.uuid", a.config.UUID),
			attribute.String("server.url", a.config.ServerURL.String()),
			attribute.String("net.peer.name", a.config.ServerURL.Hostname()),
			attribute.String("net.peer.port", a.config.ServerURL.Port()),
		),
	)

	// Connect WebSocket
	agentlog.Logger.Info().Msg("Connecting to server via WebSocket...")
	conn, err := websocket.Connect(hsCtx, a.config, tlsConfig)
	if err != nil {
		hsSpan.RecordError(err)
		hsSpan.SetStatus(codes.Error, "WebSocket dial failed")
		hsSpan.End()
		return fmt.Errorf("WebSocket connection failed: %w", err)
	}
	defer conn.Close()
	a.conn = conn
	a.lastAck = time.Now() // reset heartbeat timer on fresh connection
	a.missedAckLogged = false
	agentlog.Logger.Info().Msg("WebSocket connected")

	// Send join so the server establishes the channel
	a.sendJoin()

	hsSpan.SetStatus(codes.Ok, "connected")
	hsSpan.End()

	// Start ping ticker for heartbeats
	pingTicker := time.NewTicker(a.config.HeartbeatInterval)
	defer pingTicker.Stop()

	// Start idle timeout ticker (elastic agents only — IdleTimeout > 0).
	// When the agent is idle longer than IdleTimeout, it exits cleanly so
	// the supervisor (docker/process-compose) can terminate the container.
	var idleTicker *time.Ticker
	var idleTickerChan <-chan time.Time
	if a.config.IdleTimeout > 0 {
		// Check every second whether idle too long
		idleTicker = time.NewTicker(1 * time.Second)
		defer idleTicker.Stop()
		idleTickerChan = idleTicker.C
		agentlog.Logger.Info().Dur("idle_timeout", a.config.IdleTimeout).Msg("Elastic agent: idle timeout enabled")
	}

	// Main event loop
	for {
		select {
		case <-ctx.Done():
			return nil

		case <-idleTickerChan:
			if a.state == "Idle" && !a.idleSince.IsZero() {
				if time.Since(a.idleSince) >= a.config.IdleTimeout {
					agentlog.Logger.Info().Dur("idle_duration", time.Since(a.idleSince).Round(time.Second)).Dur("idle_timeout", a.config.IdleTimeout).Msg("Elastic agent idle timeout reached, shutting down cleanly")
					return nil
				}
			}

		case <-pingTicker.C:
			// Warn if server hasn't acknowledged the previous ping within 2× heartbeat window.
			if ackAge := time.Since(a.lastAck); ackAge > a.config.HeartbeatInterval*2 {
				if !a.missedAckLogged {
					agentlog.Logger.Warn().Dur("since_last_ack", ackAge.Round(time.Second)).Msg("Server not acknowledging heartbeats")
					a.missedAckLogged = true
				}
			}
			a.sendPing()

		case msg, ok := <-conn.Receive():
			if !ok {
				agentlog.Logger.Info().Msg("WebSocket disconnected (receive channel closed); will reconnect")
				return fmt.Errorf("WebSocket connection closed")
			}
			if err := a.handleMessage(msg); err != nil {
				agentlog.Logger.Info().Err(err).Msg("Error handling message")
			}
		}
	}
}

// handleMessage processes incoming messages from server
func (a *Agent) handleMessage(msg *protocol.Message) error {
	switch msg.Action {
	case "phx_reply":
		// Phoenix channel reply to our ping (heartbeat ack). Connection is active.
		a.lastAck = time.Now()
		a.missedAckLogged = false

	case "presence_diff":
		// Phoenix Presence broadcast (server tracks who is on the channel). No action needed.
		// Ignore silently to avoid log noise.

	case protocol.SetCookieAction:
		// Server now sends %{"cookie" => ..., "traceparent" => ...}
		// Extract cookie for auth, traceparent for cross-service tracing.
		cookiePayload := msg.DataCookiePayload()
		a.cookie = cookiePayload.Cookie
		a.conn.SetCookie(cookiePayload.Cookie)
		preview := cookiePayload.Cookie
		if len(preview) > 8 {
			preview = preview[:8] + "..."
		}
		agentlog.Logger.Info().
			Str("cookie_preview", preview).
			Str("traceparent", cookiePayload.TraceParent).
			Int("traceparent_len", len(cookiePayload.TraceParent)).
			Msg("Server set agent cookie")

		// Trace cookie exchange linked to server's agent.connect span
		cookieCtx := telemetry.ParentContextFromTraceParent(
			context.Background(), cookiePayload.TraceParent, cookiePayload.TraceState)
		_, cookieSpan := otel.Tracer("gocd-agent").Start(cookieCtx, "agent.cookie.exchange",
			trace.WithAttributes(attribute.String("agent.uuid", a.config.UUID)))
		cookieSpan.End()

	case protocol.ReregisterAction:
		agentlog.Logger.Info().Msg("Server requested re-registration")
		// Clean up and exit - supervisor will restart
		return fmt.Errorf("re-registration requested")

	case protocol.CancelBuildAction:
		buildID := msg.BuildIdFromData()
		a.buildMu.Lock()
		cancelFn := a.cancelBuildFn
		matches := a.currentBuild == buildID
		a.buildMu.Unlock()
		if matches && cancelFn != nil {
			agentlog.Logger.Info().Str("build_id", buildID).Msg("Cancelling build")
			cancelFn()
		} else if buildID != "" {
			agentlog.Logger.Info().Str("build_id", buildID).Str("current_build", a.currentBuild).Msg("Cancel requested for non-current build")
		}

	case protocol.BuildAction:
		build := msg.DataBuild()
		if build != nil {
			agentlog.Logger.Info().Str("build_id", build.BuildId).Str("locator", build.BuildLocatorForDisplay).Msg("Build assigned")
			a.handleBuild(build)
		} else {
			agentlog.Logger.Info().Msg("Build assigned but failed to parse payload")
		}

	case "phx_close":
		// Server closed the channel (e.g. duplicate join or intentional close); treat as normal close so we reconnect once
		agentlog.Logger.Info().Msg("Server closed channel (phx_close); will reconnect")
		return fmt.Errorf("channel closed by server")

	default:
		// Unhandled action: likely a bug (new server message we don't support, or typo).
		agentlog.Logger.Info().Str("action", msg.Action).Msg("Unknown message action")
	}

	return nil
}

// sendJoin sends the initial join so the server establishes the channel (once per connection).
func (a *Agent) sendJoin() {
	info := a.getRuntimeInfo()
	msg := protocol.JoinMessage(info)
	a.conn.Send(msg)
}

// sendPing sends a ping/heartbeat to the server
func (a *Agent) sendPing() {
	info := a.getRuntimeInfo()
	msg := protocol.PingMessage(info)
	a.conn.Send(msg)
}

// getRuntimeInfo returns current agent runtime information
func (a *Agent) getRuntimeInfo() *protocol.AgentRuntimeInfo {
	return &protocol.AgentRuntimeInfo{
		Identifier: &protocol.AgentIdentifier{
			HostName:  a.config.Hostname,
			IpAddress: a.config.IPAddress,
			Uuid:      a.config.UUID,
		},
		BuildingInfo: &protocol.AgentBuildingInfo{
			BuildingInfo: "",
			BuildLocator: "",
		},
		RuntimeStatus:                a.state,
		Location:                     a.config.WorkingDir,
		UsableSpace:                  getUsableSpace(),
		OperatingSystemName:          runtime.GOOS,
		Cookie:                       a.cookie,
		ElasticPluginId:              a.config.ElasticPluginID,
		ElasticAgentId:               a.config.ElasticAgentID,
		SupportsBuildCommandProtocol: true,
	}
}

// handleBuild executes a build
func (a *Agent) handleBuild(build *protocol.Build) {
	a.state = "Building"
	defer func() {
		a.state = "Idle"
		// Reset idle timer when build completes — elastic agents start counting idle time from here.
		a.idleSince = time.Now()
	}()

	ctx, cancel := context.WithCancel(context.Background())
	a.buildMu.Lock()
	a.currentBuild = build.BuildId
	a.cancelBuildFn = cancel
	a.buildMu.Unlock()
	defer func() {
		a.buildMu.Lock()
		a.currentBuild = ""
		a.cancelBuildFn = nil
		a.buildMu.Unlock()
	}()

	// Extract W3C traceparent from server build payload → link agent spans
	// under the server's pipeline.trigger trace.
	agentlog.Logger.Info().Str("traceparent", build.TraceParent).Int("traceparent_len", len(build.TraceParent)).Msg("Build traceparent")
	parentCtx := telemetry.ParentContextFromTraceParent(ctx, build.TraceParent, build.TraceState)

	tracer := otel.Tracer("gocd-agent")
	buildCtx, buildSpan := tracer.Start(parentCtx, "agent.build",
		trace.WithAttributes(
			attribute.String("build.id", build.BuildId),
			attribute.String("build.locator", build.BuildLocator),
		),
	)
	defer buildSpan.End()

	agentlog.Logger.Info().Str("build_id", build.BuildId).Msg("Executing build")
	if build.BuildCommand != nil {
		agentlog.Logger.Info().Str("cmd_name", build.BuildCommand.Name).Str("cmd", build.BuildCommand.Command).Int("subcommands", len(build.BuildCommand.SubCommands)).Msg("Build command")
	}
	a.reportStatus(build.BuildId, "Building", "")

	result := "Passed"
	if build.BuildCommand != nil && (build.BuildCommand.Command != "" || len(build.BuildCommand.SubCommands) > 0) {
		if err := a.runBuildCommand(buildCtx, build); err != nil {
			if err == context.Canceled {
				result = "Cancelled"
				buildSpan.SetStatus(codes.Error, "build cancelled")
				agentlog.Logger.Info().Str("build_id", build.BuildId).Msg("Build was cancelled")
			} else {
				agentlog.Logger.Info().Err(err).Msg("Build command failed")
				result = "Failed"
				buildSpan.SetStatus(codes.Error, err.Error())
				buildSpan.RecordError(err)
			}
		}
	} else {
		// No command: minimal success
		select {
		case <-time.After(500 * time.Millisecond):
		case <-ctx.Done():
			result = "Cancelled"
			buildSpan.SetStatus(codes.Error, "build cancelled")
		}
	}

	buildSpan.SetAttributes(attribute.String("build.result", result))
	a.reportStatus(build.BuildId, "Completing", result)
	a.reportStatus(build.BuildId, "Completed", result)
}

// runBuildCommand runs the build's command (or subCommands in sequence) in the agent working dir.
// When build.ConsoleUrl is set, stdout/stderr are captured and streamed to that URL with timestamp prefix.
// ctx can be cancelled to abort the build (e.g. cancelBuild from server).
func (a *Agent) runBuildCommand(ctx context.Context, build *protocol.Build) error {
	cmd := build.BuildCommand
	if cmd == nil {
		return nil
	}
	env := make(map[string]string)
	return a.executeCommandTree(ctx, build, cmd, env)
}

func (a *Agent) executeCommandTree(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand, env map[string]string) error {
	if len(cmd.SubCommands) > 0 {
		for _, sub := range cmd.SubCommands {
			if err := a.executeCommandTree(ctx, build, sub, env); err != nil {
				return err
			}
		}
		return nil
	}
	return a.runOneCommand(ctx, build, cmd, env)
}

// runOneCommand runs a single BuildCommand (command + args), streaming output to build.ConsoleUrl when set.
// ctx can be cancelled to kill the process (returns context.Canceled).
func (a *Agent) runOneCommand(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand, env map[string]string) error {
	tracer := otel.Tracer("gocd-agent")
	spanName := "agent.cmd." + cmd.Name
	cmdCtx, cmdSpan := tracer.Start(ctx, spanName,
		trace.WithAttributes(
			attribute.String("build.id", build.BuildId),
			attribute.String("cmd.name", cmd.Name),
			attribute.String("cmd.command", cmd.Command),
		),
	)
	defer cmdSpan.End()

	switch cmd.Name {
	case "uploadArtifact":
		return a.runUploadArtifact(cmdCtx, build, cmd)
	case "fetchArtifact":
		return a.runFetchArtifact(cmdCtx, build, cmd)
	case "export":
		var name, value string
		if cmd.Attributes != nil {
			if n, ok := cmd.Attributes["name"].(string); ok {
				name = n
			}
			if v, ok := cmd.Attributes["value"].(string); ok {
				value = v
			}
		}
		if name == "" && len(cmd.Args) >= 2 {
			name = cmd.Args[0]
			value = cmd.Args[1]
		}
		if name == "" && cmd.Command != "" {
			name = cmd.Command
			if len(cmd.Args) > 0 {
				value = cmd.Args[0]
			}
		}
		if name != "" {
			env[name] = value
			agentlog.Logger.Info().Str("name", name).Msg("Exported env var")
			cmdSpan.SetAttributes(attribute.String("export.name", name))
		}
		return nil
	}

	path := cmd.Command
	if path == "" {
		return nil
	}
	dir := a.config.WorkingDir
	if cmd.WorkingDir != "" {
		dir = cmd.WorkingDir
	}
	absDir, err := filepath.Abs(dir)
	if err != nil {
		cmdSpan.RecordError(err)
		cmdSpan.SetStatus(codes.Error, err.Error())
		return fmt.Errorf("working dir: %w", err)
	}

	cleanedPath := filepath.Clean(path)
	resolvedPath, err := exec.LookPath(cleanedPath)
	if err != nil {
		resolvedPath = cleanedPath
	}

	cmdSpan.SetAttributes(
		attribute.String("cmd.path", resolvedPath),
		attribute.String("cmd.working_dir", absDir),
	)

	// codeql[go/command-injection]: CI/CD agent executing admin-configured pipeline
	// commands. Path is sanitized via filepath.Clean + exec.LookPath. Args are
	// admin-controlled server-side, not arbitrary user input.
	c := exec.CommandContext(cmdCtx, resolvedPath, cmd.Args...)
	c.Dir = absDir

	// Merge environment variables.
	// Base is the agent's own environment (so docker, PATH, etc. are inherited).
	// Inject OTEL endpoint pointing at the agent's local relay so spawned processes
	// (including docker containers on any platform) can push spans without knowing
	// the collector address.
	c.Env = os.Environ()
	if relayEp := telemetry.OTLPRelayEndpoint(); relayEp != "" {
		c.Env = append(c.Env, "OTEL_EXPORTER_OTLP_ENDPOINT=http://"+relayEp)
		// Also set Docker host endpoint for containers spawned via docker run.
		// 127.0.0.1 from inside a container points to the container, not the host.
		if dhEp := telemetry.OTLPDockerHostEndpoint(); dhEp != "" {
			c.Env = append(c.Env, "OTEL_EXPORTER_OTLP_ENDPOINT_DOCKER=http://"+dhEp)
		}
	}
	for k, v := range env {
		if isDangerousEnvVar(k) {
			agentlog.Logger.Warn().Str("env_var", k).Msg("Blocked dangerous environment variable")
			continue
		}
		c.Env = append(c.Env, fmt.Sprintf("%s=%s", k, v))
	}

	if build.ConsoleUrl != "" {
		stdoutPipe, _ := c.StdoutPipe()
		stderrPipe, _ := c.StderrPipe()
		c.Stdin = nil
		if err := c.Start(); err != nil {
			cmdSpan.RecordError(err)
			cmdSpan.SetStatus(codes.Error, err.Error())
			return err
		}
		var wg sync.WaitGroup
		streamToConsole := func(prefix string, r io.Reader) {
			defer wg.Done()
			a.streamReaderToConsole(build.ConsoleUrl, prefix, r)
		}
		wg.Add(2)
		go streamToConsole("", stdoutPipe)
		go streamToConsole("stderr: ", stderrPipe)
		wg.Wait()
		err := c.Wait()
		if err != nil {
			if cmdCtx.Err() == context.Canceled {
				cmdSpan.SetAttributes(attribute.String("cmd.result", "cancelled"))
				return context.Canceled
			}
			cmdSpan.RecordError(err)
			cmdSpan.SetStatus(codes.Error, err.Error())
			setExitCode(cmdSpan, err)
			return err
		}
		cmdSpan.SetAttributes(attribute.Int("cmd.exit_code", 0))
		return nil
	}

	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	err = c.Run()
	if err != nil {
		if cmdCtx.Err() == context.Canceled {
			cmdSpan.SetAttributes(attribute.String("cmd.result", "cancelled"))
			return context.Canceled
		}
		cmdSpan.RecordError(err)
		cmdSpan.SetStatus(codes.Error, err.Error())
		setExitCode(cmdSpan, err)
		return err
	}
	cmdSpan.SetAttributes(attribute.Int("cmd.exit_code", 0))
	return nil
}

// setExitCode extracts the process exit code from an exec error and sets it as a span attribute.
func setExitCode(span trace.Span, err error) {
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		span.SetAttributes(attribute.Int("cmd.exit_code", exitErr.ExitCode()))
	} else {
		span.SetAttributes(attribute.Int("cmd.exit_code", -1))
	}
}

func (a *Agent) httpClient() (*http.Client, error) {
	if a.registrar == nil {
		return nil, fmt.Errorf("registrar is not initialized")
	}
	tlsConfig, err := a.registrar.CreateTLSConfig()
	if err != nil {
		return nil, err
	}
	return &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: tlsConfig,
		},
	}, nil
}

func (a *Agent) runUploadArtifact(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand) error {
	agentlog.Logger.Info().Str("src", cmd.Src).Str("dest", cmd.Dest).Msg("Executing uploadArtifact")
	dir := a.config.WorkingDir
	if cmd.WorkingDir != "" {
		dir = cmd.WorkingDir
	}
	absDir, err := filepath.Abs(dir)
	if err != nil {
		return fmt.Errorf("working dir: %w", err)
	}

	srcPath, err := a.validatePath(absDir, cmd.Src)
	if err != nil {
		return fmt.Errorf("invalid artifact source path: %w", err)
	}

	if _, err := os.Stat(srcPath); err != nil {
		return fmt.Errorf("artifact source path %q does not exist: %w", srcPath, err)
	}

	return a.uploadArtifact(ctx, build, cmd, srcPath)
}

func (a *Agent) uploadArtifact(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand, srcPath string) error {
	msg := fmt.Sprintf("Uploading artifact %s to %s on server...\n", cmd.Src, cmd.Dest)
	_ = a.postConsole(build.ConsoleUrl, time.Now().Format("15:04:05.000")+" "+msg)

	zipPath, err := zipSource(srcPath)
	if err != nil {
		return fmt.Errorf("zip source failed: %w", err)
	}
	defer os.Remove(zipPath)

	checksum, err := fileMD5(zipPath)
	if err != nil {
		return fmt.Errorf("calculate md5 failed: %w", err)
	}

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	zipFile, err := os.Open(zipPath)
	if err != nil {
		return err
	}
	defer zipFile.Close()

	part, err := writer.CreateFormFile("zipfile", filepath.Base(zipPath))
	if err != nil {
		return err
	}
	if _, err := io.Copy(part, zipFile); err != nil {
		return err
	}

	checksumKey := cmd.Dest
	if checksumKey == "" {
		checksumKey = filepath.Base(srcPath)
	}
	checksumLine := fmt.Sprintf("%s:%s\n", checksumKey, checksum)

	checksumPart, err := writer.CreateFormFile("file_checksum", "cruise-output/md5.checksum")
	if err != nil {
		return err
	}
	if _, err := io.WriteString(checksumPart, checksumLine); err != nil {
		return err
	}

	if err := writer.Close(); err != nil {
		return err
	}

	uploadURL := build.ArtifactUploadBaseUrl
	if !strings.HasSuffix(uploadURL, "/") {
		uploadURL += "/"
	}
	uploadURL += cmd.Dest

	validatedUploadURL, err := a.validateURL(uploadURL)
	if err != nil {
		return fmt.Errorf("untrusted artifact upload URL: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, validatedUploadURL, body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	client, err := a.httpClient()
	if err != nil {
		return fmt.Errorf("create HTTP client failed: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("http upload request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("upload artifact failed: status %s, body: %q", resp.Status, string(respBody))
	}

	successMsg := fmt.Sprintf("Successfully uploaded artifact %s to %s.\n", cmd.Src, cmd.Dest)
	_ = a.postConsole(build.ConsoleUrl, time.Now().Format("15:04:05.000")+" "+successMsg)
	return nil
}

func (a *Agent) runFetchArtifact(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand) error {
	agentlog.Logger.Info().Str("src", cmd.Src).Str("dest", cmd.Dest).Msg("Executing fetchArtifact")
	dir := a.config.WorkingDir
	if cmd.WorkingDir != "" {
		dir = cmd.WorkingDir
	}
	absDir, err := filepath.Abs(dir)
	if err != nil {
		return fmt.Errorf("working dir: %w", err)
	}

	destPath, err := a.validatePath(absDir, cmd.Dest)
	if err != nil {
		return fmt.Errorf("invalid artifact destination path: %w", err)
	}

	return a.fetchArtifact(ctx, build, cmd, destPath)
}

func (a *Agent) fetchArtifact(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand, destPath string) error {
	msg := fmt.Sprintf("Fetching artifact %s to %s...\n", cmd.Src, cmd.Dest)
	_ = a.postConsole(build.ConsoleUrl, time.Now().Format("15:04:05.000")+" "+msg)

	downloadURL := cmd.Src
	if !strings.HasPrefix(downloadURL, "http://") && !strings.HasPrefix(downloadURL, "https://") {
		cleanedSrc := strings.TrimPrefix(cmd.Src, "/")
		parts := strings.Split(cleanedSrc, "/")
		if len(parts) >= 5 {
			filesBase := getFilesBaseURL(build.ArtifactUploadBaseUrl)
			downloadURL = filesBase + "/" + cleanedSrc
		} else {
			downloadURL = build.ArtifactUploadBaseUrl
			if !strings.HasSuffix(downloadURL, "/") {
				downloadURL += "/"
			}
			downloadURL += cleanedSrc
		}
	}

	validatedDownloadURL, err := a.validateURL(downloadURL)
	if err != nil {
		return fmt.Errorf("untrusted artifact download URL: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, validatedDownloadURL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/zip")

	client, err := a.httpClient()
	if err != nil {
		return err
	}

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("fetch artifact failed with status %s: %s", resp.Status, string(respBody))
	}

	contentType := resp.Header.Get("Content-Type")
	isZip := contentType == "application/zip" || strings.HasSuffix(validatedDownloadURL, ".zip")

	if isZip {
		tmpFile, err := os.CreateTemp("", "gocd-fetch-*.zip")
		if err != nil {
			return err
		}
		defer os.Remove(tmpFile.Name())
		defer tmpFile.Close()

		if _, err := io.Copy(tmpFile, resp.Body); err != nil {
			return err
		}
		_ = tmpFile.Close()

		if err := unzipSecurely(tmpFile.Name(), destPath); err != nil {
			return fmt.Errorf("unzip failed: %w", err)
		}
	} else {
		if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
			return err
		}
		out, err := os.Create(destPath)
		if err != nil {
			return err
		}
		defer out.Close()

		if _, err := io.Copy(out, resp.Body); err != nil {
			return err
		}
	}

	successMsg := fmt.Sprintf("Successfully fetched artifact to %s.\n", cmd.Dest)
	_ = a.postConsole(build.ConsoleUrl, time.Now().Format("15:04:05.000")+" "+successMsg)
	return nil
}

func getFilesBaseURL(uploadURL string) string {
	for _, pattern := range []string{"/files", "/go/files", "/remoting/files"} {
		if idx := strings.Index(uploadURL, pattern); idx != -1 {
			return uploadURL[:idx] + pattern
		}
	}
	return uploadURL
}

func fileMD5(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := md5.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func zipSource(srcPath string) (string, error) {
	fi, err := os.Stat(srcPath)
	if err != nil {
		return "", err
	}

	tmpFile, err := os.CreateTemp("", "gocd-upload-*.zip")
	if err != nil {
		return "", err
	}

	success := false
	defer func() {
		if !success {
			tmpFile.Close()
			os.Remove(tmpFile.Name())
		}
	}()

	zw := zip.NewWriter(tmpFile)

	if !fi.IsDir() {
		f, err := os.Open(srcPath)
		if err != nil {
			return "", err
		}
		defer f.Close()

		w, err := zw.Create(filepath.Base(srcPath))
		if err != nil {
			return "", err
		}
		if _, err := io.Copy(w, f); err != nil {
			return "", err
		}
	} else {
		err = filepath.Walk(srcPath, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if info.IsDir() {
				return nil
			}

			rel, err := filepath.Rel(srcPath, path)
			if err != nil {
				return err
			}

			f, err := os.Open(path)
			if err != nil {
				return err
			}
			defer f.Close()

			w, err := zw.Create(rel)
			if err != nil {
				return err
			}
			if _, err := io.Copy(w, f); err != nil {
				return err
			}
			return nil
		})
		if err != nil {
			return "", err
		}
	}

	if err := zw.Close(); err != nil {
		return "", err
	}
	if err := tmpFile.Close(); err != nil {
		return "", err
	}

	success = true
	return tmpFile.Name(), nil
}

func unzipSecurely(zipPath string, destDir string) error {
	destDir, err := filepath.Abs(destDir)
	if err != nil {
		return err
	}

	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer r.Close()

	for _, f := range r.File {
		cleanedPath := filepath.Clean(f.Name)
		if strings.HasPrefix(cleanedPath, ".."+string(filepath.Separator)) || cleanedPath == ".." || filepath.IsAbs(cleanedPath) {
			return fmt.Errorf("illegal file path in zip (Zip Slip detected): %s", f.Name)
		}

		targetPath := filepath.Join(destDir, cleanedPath)
		absTarget, err := filepath.Abs(targetPath)
		if err != nil {
			return fmt.Errorf("invalid absolute path: %w", err)
		}

		rel, err := filepath.Rel(destDir, absTarget)
		if err != nil || strings.HasPrefix(rel, "..") {
			return fmt.Errorf("illegal file path in zip (Zip Slip boundary escape): %s", f.Name)
		}

		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(absTarget, 0755); err != nil {
				return err
			}
			continue
		}

		if err := os.MkdirAll(filepath.Dir(absTarget), 0755); err != nil {
			return err
		}

		outFile, err := os.OpenFile(absTarget, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			return err
		}

		rc, err := f.Open()
		if err != nil {
			outFile.Close()
			return err
		}

		_, err = io.Copy(outFile, rc)
		rc.Close()
		outFile.Close()
		if err != nil {
			return err
		}
	}

	return nil
}

// streamReaderToConsole reads lines from r, prefixes each with "HH:mm:ss.SSS [prefix]", and POSTs to consoleURL.
func (a *Agent) streamReaderToConsole(consoleURL, linePrefix string, r io.Reader) {
	defer func() {
		if r := recover(); r != nil {
			agentlog.Logger.Info().Interface("panic", r).Msg("Recovered panic in streamReaderToConsole")
		}
	}()

	reader := bufio.NewReaderSize(r, 64*1024)
	for {
		line, isPrefix, err := reader.ReadLine()
		if len(line) > 0 {
			content := string(line)
			ts := time.Now().Format("15:04:05.000")
			payload := ts + " " + linePrefix + content
			if isPrefix {
				payload += " [truncated...]\n"
			} else {
				payload += "\n"
			}
			if err := a.postConsole(consoleURL, payload); err != nil {
				agentlog.Logger.Info().Err(err).Msg("Console POST failed")
			}
		}
		if err != nil {
			if err != io.EOF {
				payload := time.Now().Format("15:04:05.000") + " [reader error] " + err.Error() + "\n"
				_ = a.postConsole(consoleURL, payload)
			}
			break
		}
	}
}

// postConsole POSTs body as text/plain to the given URL.
func (a *Agent) postConsole(consoleURL, body string) error {
	if consoleURL == "" {
		return nil
	}
	validatedURL, err := a.validateURL(consoleURL)
	if err != nil {
		return fmt.Errorf("untrusted console URL: %w", err)
	}
	req, err := http.NewRequest(http.MethodPost, validatedURL, strings.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "text/plain; charset=utf-8")

	client, err := a.httpClient()
	var doer interface {
		Do(*http.Request) (*http.Response, error)
	} = http.DefaultClient
	if err == nil && client != nil {
		doer = client
	}

	resp, err := doer.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		return fmt.Errorf("console POST %s: %s", resp.Status, bytes.TrimSpace(mustRead(resp.Body)))
	}
	return nil
}

func mustRead(r io.Reader) []byte {
	b, _ := io.ReadAll(r)
	return b
}

// reportStatus reports job status to server
func (a *Agent) reportStatus(buildID, jobState, result string) {
	report := &protocol.Report{
		BuildId:          buildID,
		JobState:         jobState,
		Result:           result,
		AgentRuntimeInfo: a.getRuntimeInfo(),
	}

	var msg *protocol.Message
	switch jobState {
	case "Completed":
		msg = protocol.ReportCompletedMessage(report)
	case "Completing":
		msg = protocol.ReportCompletingMessage(report)
	default:
		msg = protocol.ReportCurrentStatusMessage(report)
	}

	a.conn.Send(msg)
}

// getUsableSpace returns available disk space
func getUsableSpace() int64 {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(".", &stat); err != nil {
		// Fallback to 10GB
		return 10 * 1024 * 1024 * 1024
	}
	return int64(stat.Bavail) * int64(stat.Bsize)
}

// validateURL validates that the URL is a HTTP/HTTPS request matching the configured GoCD server host to mitigate SSRF.
// To satisfy static analysis, we reconstruct the URL using the trusted configured server URL's scheme and host.
func (a *Agent) validateURL(rawURL string) (string, error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return "", fmt.Errorf("invalid URL: %w", err)
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return "", fmt.Errorf("unsupported URL scheme: %s", u.Scheme)
	}
	if u.Host != a.config.ServerURL.Host {
		return "", fmt.Errorf("untrusted URL host: %s (must match configured GoCD server %s)", u.Host, a.config.ServerURL.Host)
	}
	// Reconstruct securely using trusted host and scheme
	target := *a.config.ServerURL
	target.Path = u.Path
	target.RawQuery = u.RawQuery
	target.Fragment = u.Fragment
	return target.String(), nil
}

// validatePath cleans targetPath, resolves it relative to baseDir, and ensures it does not escape baseDir boundary to mitigate path traversal.
func (a *Agent) validatePath(baseDir, targetPath string) (string, error) {
	absBase, err := filepath.Abs(baseDir)
	if err != nil {
		return "", fmt.Errorf("invalid base dir: %w", err)
	}

	var absTarget string
	if filepath.IsAbs(targetPath) {
		absTarget = filepath.Clean(targetPath)
	} else {
		absTarget = filepath.Join(absBase, targetPath)
	}

	absTarget, err = filepath.Abs(absTarget)
	if err != nil {
		return "", fmt.Errorf("invalid target path: %w", err)
	}

	rel, err := filepath.Rel(absBase, absTarget)
	if err != nil {
		return "", fmt.Errorf("path relation error: %w", err)
	}

	if rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("path traversal attempt detected: %s is outside of %s", targetPath, baseDir)
	}

	return absTarget, nil
}

// isDangerousEnvVar returns true for environment variables that can be used to
// inject code into the spawned process (dynamic linker preload, library path
// hijacking, etc.). These are never legitimate in a CI/CD pipeline.
func isDangerousEnvVar(k string) bool {
	switch strings.ToUpper(k) {
	case "LD_PRELOAD", "LD_LIBRARY_PATH",
		"DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH",
		"PYTHONPATH", "PYTHONSTARTUP", "PYTHONOPTIMIZE",
		"PERL5LIB", "PERLLIB",
		"RUBYLIB", "RUBYOPT",
		"GEM_PATH", "GEM_HOME",
		"NODE_PATH", "NODE_OPTIONS",
		"CLASSPATH", "JAVA_TOOL_OPTIONS", "JAVA_OPTIONS", "_JAVA_OPTIONS",
		"GOPATH":
		return true
	}
	return false
}
