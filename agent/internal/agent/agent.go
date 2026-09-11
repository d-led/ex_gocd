// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package agent

import (
	"archive/zip"
	"bufio"
	"bytes"
	"context"
	"crypto/md5"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"mime/multipart"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/d-led/ex_gocd/agent/internal/config"
	agentdocker "github.com/d-led/ex_gocd/agent/internal/docker"
	agentlog "github.com/d-led/ex_gocd/agent/internal/log"
	"github.com/d-led/ex_gocd/agent/internal/registration"
	"github.com/d-led/ex_gocd/agent/internal/remoting"
	"github.com/d-led/ex_gocd/agent/internal/telemetry"
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
	client    *remoting.Client
	cookie    string
	state     string

	// Elastic agent idle timeout: when set (>0), agent self-terminates after idle this long.
	// idleSince is set when entering Idle state, cleared when building.
	idleSince time.Time

	// Current build: guarded by buildMu.
	buildMu        sync.Mutex
	currentBuild   string             // buildId of running build, or ""
	currentLocator string             // build locator of running build, or ""
	cancelBuildFn  context.CancelFunc // call to cancel current build
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

	// Clean up stale job directories from previous runs on startup.
	a.cleanupJobDirs()

	// Start periodic cleanup if configured
	if a.config.CleanupInterval > 0 {
		go a.periodicCleanup(startCtx, a.config.CleanupInterval)
	}
	// Register with server
	agentlog.Logger.Info().Msg("Registering with server...")
	if err := a.registrar.Register(); err != nil {
		startupSpan.RecordError(err)
		startupSpan.SetStatus(codes.Error, "registration failed")
		return fmt.Errorf("%w: registration failed: %w", ErrServerUnavailable, err)
	}
	agentlog.Logger.Info().Msg("Registration successful")

	// Build the HTTP remoting client (TLS config is nil for plain HTTP).
	tlsConfig, err := a.registrar.CreateTLSConfig()
	if err != nil {
		return fmt.Errorf("%w: failed to create TLS config: %w", ErrServerUnavailable, err)
	}

	client, err := remoting.NewClient(a.config, tlsConfig)
	if err != nil {
		return fmt.Errorf("%w: failed to create remoting client: %w", ErrServerUnavailable, err)
	}
	a.client = client

	// Official agents fetch their session cookie once, right after registration.
	cookieCtx, cookieSpan := tracer.Start(ctx, "agent.cookie.exchange",
		trace.WithAttributes(attribute.String("agent.uuid", a.config.UUID)))
	if cookie, err := client.GetCookie(cookieCtx, a.runtimeInfo()); err == nil {
		a.cookie = cookie
	} else {
		agentlog.Logger.Warn().Err(err).Msg("get_cookie failed; continuing without a session cookie")
	}
	cookieSpan.End()

	return a.run(ctx)
}

// run runs the agent's main poll loop: ping for heartbeats, get_work for
// assignments, and idle-timeout enforcement. It returns only when ctx is done.
func (a *Agent) run(ctx context.Context) error {
	pingTicker := time.NewTicker(a.config.HeartbeatInterval)
	defer pingTicker.Stop()

	workTicker := time.NewTicker(a.config.WorkPollInterval)
	defer workTicker.Stop()

	// Idle timeout ticker (elastic agents only — IdleTimeout > 0). When the
	// agent stays idle longer than IdleTimeout it exits cleanly so the
	// supervisor (docker/process-compose) can terminate the container.
	var idleTicker *time.Ticker
	var idleTickerChan <-chan time.Time
	if a.config.IdleTimeout > 0 {
		idleTicker = time.NewTicker(1 * time.Second)
		defer idleTicker.Stop()
		idleTickerChan = idleTicker.C
		agentlog.Logger.Info().Dur("idle_timeout", a.config.IdleTimeout).Msg("Elastic agent: idle timeout enabled")
	}

	for {
		select {
		case <-ctx.Done():
			agentlog.Logger.Info().Msg("Agent shutting down...")
			return nil

		case <-idleTickerChan:
			if a.state == "Idle" && !a.idleSince.IsZero() && time.Since(a.idleSince) >= a.config.IdleTimeout {
				agentlog.Logger.Info().Dur("idle_duration", time.Since(a.idleSince).Round(time.Second)).Dur("idle_timeout", a.config.IdleTimeout).Msg("Elastic agent idle timeout reached, shutting down cleanly")
				return nil
			}

		case <-pingTicker.C:
			a.ping(ctx)

		case <-workTicker.C:
			a.pollWork(ctx)
		}
	}
}

// ping sends one heartbeat.
func (a *Agent) ping(ctx context.Context) {
	if err := a.client.Ping(ctx, a.runtimeInfo()); err != nil {
		agentlog.Logger.Warn().Err(err).Msg("ping failed")
	}
}

// pollWork asks the server for an assignment and runs it in the background so
// heartbeats keep flowing while a build executes.
func (a *Agent) pollWork(ctx context.Context) {
	work, err := a.client.GetWork(ctx, a.runtimeInfo())
	if err != nil {
		agentlog.Logger.Warn().Err(err).Msg("get_work failed")
		return
	}
	if work == nil {
		return
	}

	a.buildMu.Lock()
	busy := a.currentBuild != ""
	a.buildMu.Unlock()
	if busy {
		agentlog.Logger.Warn().Str("build_id", a.currentBuild).Msg("Ignoring assignment while a build is already running")
		return
	}

	go a.executeWork(work)
}

// runtimeInfo returns the agent's current self-description for remoting calls.
func (a *Agent) runtimeInfo() *protocol.AgentRuntimeInfo {
	a.buildMu.Lock()
	locator := a.currentLocator
	a.buildMu.Unlock()

	buildingInfo := &protocol.AgentBuildingInfo{}
	if locator != "" {
		buildingInfo.BuildingInfo = locator
		buildingInfo.BuildLocator = locator
	}

	return &protocol.AgentRuntimeInfo{
		Type: "AgentRuntimeInfo",
		Identifier: &protocol.AgentIdentifier{
			HostName:  a.config.Hostname,
			IpAddress: a.config.IPAddress,
			Uuid:      a.config.UUID,
		},
		BuildingInfo:                 buildingInfo,
		RuntimeStatus:                a.state,
		Location:                     a.config.WorkingDir,
		UsableSpace:                  getUsableSpace(),
		OperatingSystemName:          runtime.GOOS,
		Cookie:                       a.cookie,
		AgentBootstrapperVersion:     remoting.AgentBootstrapperVersion,
		AgentVersion:                 remoting.AgentVersion,
		ElasticPluginId:              a.config.ElasticPluginID,
		ElasticAgentId:               a.config.ElasticAgentID,
		SupportsBuildCommandProtocol: true,
	}
}

// executeWork runs one BuildWork assignment in a background goroutine.
func (a *Agent) executeWork(work *remoting.Work) {
	job := work.Assignment.JobIdentifier
	build := a.client.Build(work)

	a.state = "Building"
	defer func() {
		a.state = "Idle"
		a.idleSince = time.Now()
	}()

	a.buildMu.Lock()
	a.currentBuild = build.BuildId
	a.currentLocator = build.BuildLocator
	a.buildMu.Unlock()
	defer func() {
		a.buildMu.Lock()
		a.currentBuild = ""
		a.currentLocator = ""
		a.buildMu.Unlock()
	}()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	a.buildMu.Lock()
	a.cancelBuildFn = cancel
	a.buildMu.Unlock()
	defer func() {
		a.buildMu.Lock()
		a.cancelBuildFn = nil
		a.buildMu.Unlock()
	}()

	// Watch is_ignored so the server can cancel a discarded assignment.
	go a.watchIgnored(ctx, cancel, job)

	tracer := otel.Tracer("gocd-agent")
	buildCtx, buildSpan := tracer.Start(ctx, "agent.build",
		trace.WithAttributes(
			attribute.String("build.id", build.BuildId),
			attribute.String("build.locator", build.BuildLocator),
		),
	)
	defer buildSpan.End()

	agentlog.Logger.Info().Str("build_id", build.BuildId).Str("locator", build.BuildLocator).Msg("Executing build")
	if build.BuildCommand != nil {
		agentlog.Logger.Info().Str("cmd_name", build.BuildCommand.Name).Int("subcommands", len(build.BuildCommand.SubCommands)).Msg("Build command")
	}
	a.reportStatus(job, "Building", "")

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
		// No command: minimal success.
		select {
		case <-time.After(500 * time.Millisecond):
		case <-buildCtx.Done():
			result = "Cancelled"
			buildSpan.SetStatus(codes.Error, "build cancelled")
		}
	}

	buildSpan.SetAttributes(attribute.String("build.result", result))
	a.reportStatus(job, "Completing", result)
	a.reportStatus(job, "Completed", result)
}

// watchIgnored polls is_ignored and cancels the build when the server has
// discarded the assignment.
func (a *Agent) watchIgnored(ctx context.Context, cancel context.CancelFunc, job remoting.JobIdentifier) {
	ticker := time.NewTicker(a.config.WorkPollInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			ignored, err := a.client.IsIgnored(ctx, a.runtimeInfo(), job)
			if err != nil {
				agentlog.Logger.Warn().Err(err).Msg("is_ignored check failed")
				continue
			}
			if ignored {
				agentlog.Logger.Info().Str("locator", job.Locator()).Msg("Assignment ignored by server; cancelling build")
				cancel()
				return
			}
		}
	}
}

// reportStatus reports a job state/result back to the server.
func (a *Agent) reportStatus(job remoting.JobIdentifier, jobState, result string) {
	info := a.runtimeInfo()
	var err error
	switch jobState {
	case "Completed":
		err = a.client.ReportCompleted(context.Background(), info, job, result)
	case "Completing":
		err = a.client.ReportCompleting(context.Background(), info, job, result)
	default:
		err = a.client.ReportCurrentStatus(context.Background(), info, job, jobState)
	}
	if err != nil {
		agentlog.Logger.Warn().Err(err).Str("job_state", jobState).Str("result", result).Msg("report status failed")
	}
}

// runBuildCommand runs the build's command (or subCommands in sequence) in the agent working dir.
// When build.ConsoleUrl is set, stdout/stderr are captured and streamed to that URL with timestamp prefix.
// ctx can be cancelled to abort the build (e.g. cancelBuild from server).
//
// Before executing the command tree, the agent prepares the job working directory:
//   - Creates the per-job directory (e.g. ex_gocd_jobs/pipeline/82/ci/1/quality)
//   - Nukes any stale .git to prevent shallow-clone object corruption
//   - Runs circular cleanup of old job directories
//
// All filesystem operations use Go's os package — no shell commands — for Windows/Linux/macOS portability.
func (a *Agent) runBuildCommand(ctx context.Context, build *protocol.Build) error {
	cmd := build.BuildCommand
	if cmd == nil {
		return nil
	}

	// Prepare the job working directory (platform-safe, pure Go).
	if cmd.WorkingDir != "" {
		jobDir := cmd.WorkingDir
		if err := os.MkdirAll(jobDir, 0755); err != nil {
			return fmt.Errorf("prepare job dir %s: %w", jobDir, err)
		}
		// Nuke .git to prevent shallow-clone corruption from previous runs.
		gitDir := filepath.Join(jobDir, ".git")
		if _, err := os.Stat(gitDir); err == nil {
			if err := os.RemoveAll(gitDir); err != nil {
				agentlog.Logger.Warn().Err(err).Str("dir", gitDir).Msg("Failed to remove stale .git directory")
			}
		}
		// Circular buffer cleanup: trim old job directories.
		a.cleanupJobDirs()
	}

	env := make(map[string]string)
	return a.executeCommandTree(ctx, build, cmd, a.config.WorkingDir, env)
}

// executeCommandTree recursively executes a command tree.
// parentWorkingDir is the resolved working directory of the parent compose node.
// For leaf commands without their own WorkingDir, the parent's value is inherited.
// Relative WorkingDir values are resolved against the parent (e.g. material destination "src" → "{jobDir}/src").
func (a *Agent) executeCommandTree(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand, parentWorkingDir string, env map[string]string) error {
	// Resolve this command's working directory.
	if cmd.WorkingDir == "" {
		// Inherit from parent.
		cmd.WorkingDir = parentWorkingDir
	} else if !filepath.IsAbs(cmd.WorkingDir) {
		// Relative path (e.g. material destination "src") — resolve against parent.
		cmd.WorkingDir = filepath.Join(parentWorkingDir, cmd.WorkingDir)
	}
	// else: absolute path — use as-is.

	if len(cmd.SubCommands) > 0 {
		for _, sub := range cmd.SubCommands {
			if err := a.executeCommandTree(ctx, build, sub, cmd.WorkingDir, env); err != nil {
				return err
			}
		}
		return nil
	}

	// Ensure working directory exists (handles material destination subfolders).
	if err := os.MkdirAll(cmd.WorkingDir, 0755); err != nil {
		return fmt.Errorf("create working dir %s: %w", cmd.WorkingDir, err)
	}

	// Wrap leaf commands (except export) with ##[fold] markers for UI collapsible sections.
	// Export commands set env vars silently; the env/echo batch command already displays them.
	if cmd.Name == "export" {
		return a.runOneCommand(ctx, build, cmd, env)
	}
	return a.runOneCommandWithFold(ctx, build, cmd, env)
}

// foldLabel builds a short, safe label for a build command including key arguments.
// Mirrors GoCD's approach: masks secure env var values and URL passwords.
// Truncates to ~100 chars for safe console output.
func (a *Agent) foldLabel(cmd *protocol.BuildCommand) string {
	base := cmd.Command
	if base == "" {
		base = cmd.Name
	}

	// env (echo) with many lines: show summary instead of dumping all vars
	if cmd.Name == "env" && cmd.Command == "echo" && len(cmd.Args) == 1 {
		lines := strings.Split(cmd.Args[0], "\n")
		if len(lines) > 1 {
			return fmt.Sprintf("echo (%d env vars)", len(lines))
		}
		return truncate("echo "+cmd.Args[0], 120)
	}

	// export: show NAME=VALUE, masking secure values
	if cmd.Name == "export" && len(cmd.Args) >= 1 {
		secure := isSecure(cmd.Attributes)
		varName := cmd.Args[0]
		if secure || len(cmd.Args) < 2 {
			return "export " + varName + "=********"
		}
		return truncate("export "+varName+"="+cmd.Args[1], 120)
	}

	// Default: command + args, with URL password masking
	if len(cmd.Args) == 0 {
		return base
	}
	return truncate(buildLabelWithMaskedArgs(base, cmd.Args), 120)
}

// isSecure checks if the command has a "secure" attribute set to true.
func isSecure(attrs map[string]interface{}) bool {
	if attrs == nil {
		return false
	}
	if v, ok := attrs["secure"]; ok {
		switch val := v.(type) {
		case bool:
			return val
		case string:
			return val == "true"
		}
	}
	return false
}

// buildLabelWithMaskedArgs joins command + args, masking passwords in URL-like args.
func buildLabelWithMaskedArgs(cmd string, args []string) string {
	var b strings.Builder
	b.WriteString(cmd)
	for _, arg := range args {
		b.WriteByte(' ')
		b.WriteString(maskPasswordInArg(arg))
		if b.Len() > 100 {
			return truncate(b.String(), 117) + "..."
		}
	}
	return b.String()
}

// maskPasswordInArg replaces password-like patterns in arg with ******.
// Handles: https://user:pass@host, git@host (keeps), token-like strings in URLs.
func maskPasswordInArg(arg string) string {
	// Only mask URLs with userinfo (user:password@)
	if idx := strings.Index(arg, "://"); idx > 0 {
		rest := arg[idx+3:]
		if atIdx := strings.Index(rest, "@"); atIdx > 0 {
			userInfo := rest[:atIdx]
			hostAndPath := rest[atIdx:]
			if colonIdx := strings.Index(userInfo, ":"); colonIdx > 0 {
				return arg[:idx+3] + userInfo[:colonIdx] + ":******" + hostAndPath
			}
		}
	}
	return arg
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen]
}

// runOneCommandWithFold emits ##[fold] / ##[endfold] markers around a command's output.
// Exports get fold markers too so the UI can show each variable name.
func (a *Agent) runOneCommandWithFold(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand, env map[string]string) error {
	if build.ConsoleUrl != "" {
		label := a.foldLabel(cmd)
		_ = a.postConsole(build.ConsoleUrl, time.Now().Format("15:04:05.000")+" ##[fold]"+label+"\n")
	}
	err := a.runOneCommand(ctx, build, cmd, env)
	if build.ConsoleUrl != "" {
		_ = a.postConsole(build.ConsoleUrl, time.Now().Format("15:04:05.000")+" ##[endfold]\n")
	}
	return err
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
	// WorkingDir is already resolved by executeCommandTree (inherited from parent,
	// relative paths resolved, directory created via os.MkdirAll).
	dir := cmd.WorkingDir
	if dir == "" {
		dir = a.config.WorkingDir
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
		// Relative path not found in PATH — resolve against working directory
		if !filepath.IsAbs(cleanedPath) {
			resolvedPath = filepath.Join(absDir, cleanedPath)
		} else {
			resolvedPath = cleanedPath
		}
	}

	cmdSpan.SetAttributes(
		attribute.String("cmd.path", resolvedPath),
		attribute.String("cmd.working_dir", absDir),
	)

	// codeql[go/command-injection]: CI/CD agent executing admin-configured pipeline
	// commands. Path is sanitized via filepath.Clean + exec.LookPath. Args are
	// admin-controlled server-side, not arbitrary user input.
	// Inject agent-identity labels into docker run/create commands for
	// container traceability and orphan cleanup (Testcontainers Ryuk pattern).
	args := agentdocker.InterceptDockerArgs(resolvedPath, cmd.Args, a.config.UUID, build.BuildId)
	c := exec.Command(resolvedPath, args...)
	c.Dir = absDir
	// Setpgid creates a new process group so we can kill the entire tree on cancel.
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	// Graceful cancellation: SIGTERM → wait grace period → SIGKILL
	cancelDone := make(chan struct{})
	defer close(cancelDone)
	go func() {
		defer func() {
			if r := recover(); r != nil {
				agentlog.Logger.Error().Interface("panic", r).Msg("gracefulCancel goroutine panicked")
			}
		}()
		gracefulCancel(cmdCtx, c, cancelDone)
	}()

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
		var stdoutPipe, stderrPipe io.ReadCloser
		var pipeErr error
		stdoutPipe, pipeErr = c.StdoutPipe()
		if pipeErr != nil {
			agentlog.Logger.Warn().Err(pipeErr).Str("build_id", build.BuildId).Msg("Failed to create stdout pipe")
		}
		stderrPipe, pipeErr = c.StderrPipe()
		if pipeErr != nil {
			agentlog.Logger.Warn().Err(pipeErr).Str("build_id", build.BuildId).Msg("Failed to create stderr pipe")
		}
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

// gracefulCancel handles context cancellation with SIGTERM → grace period → SIGKILL escalation.
// The cmd must have SysProcAttr.Setpgid=true so we can signal the entire process group.
func gracefulCancel(ctx context.Context, cmd *exec.Cmd, done <-chan struct{}) {
	const gracePeriod = 10 * time.Second

	select {
	case <-ctx.Done():
	case <-done:
		return
	}

	// Brief pause to let the process start (Process is nil until Start/ Run).
	time.Sleep(50 * time.Millisecond)

	if cmd.Process == nil {
		return
	}

	pgid := -cmd.Process.Pid
	agentlog.Logger.Info().Int("pid", cmd.Process.Pid).Msg("Cancelling build — sending SIGTERM to process group")
	_ = syscall.Kill(pgid, syscall.SIGTERM)

	timer := time.NewTimer(gracePeriod)
	select {
	case <-done:
		timer.Stop()
	case <-timer.C:
		if cmd.Process != nil {
			agentlog.Logger.Info().Int("pid", cmd.Process.Pid).Msg("Build still running after grace period — sending SIGKILL to process group")
			_ = syscall.Kill(pgid, syscall.SIGKILL)
		}
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
		Timeout: 60 * time.Second,
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

// streamReaderToConsole reads lines from r, prefixes each with "HH:mm:ss.SSS [prefix]", and appends to consoleURL.
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

// postConsole appends body to the job's console log. The server expects a PUT
// with the body length in X-Go-Artifact-Size (see test/fixtures/remoting/README.md).
func (a *Agent) postConsole(consoleURL, body string) error {
	if consoleURL == "" {
		return nil
	}
	validatedURL, err := a.validateURL(consoleURL)
	if err != nil {
		return fmt.Errorf("untrusted console URL: %w", err)
	}
	req, err := http.NewRequest(http.MethodPut, validatedURL, strings.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "text/plain; charset=utf-8")
	req.Header.Set("X-Go-Artifact-Size", strconv.Itoa(len(body)))

	var client *http.Client
	if parsed, _ := url.Parse(validatedURL); parsed != nil && parsed.Scheme == "https" {
		var err error
		client, err = a.httpClient()
		if err != nil {
			return fmt.Errorf("failed to create TLS HTTP client for console post: %w", err)
		}
	} else {
		client = &http.Client{Timeout: 30 * time.Second}
	}

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		return fmt.Errorf("console upload %s: %s", resp.Status, bytes.TrimSpace(mustRead(resp.Body)))
	}
	return nil
}

func mustRead(r io.Reader) []byte {
	b, _ := io.ReadAll(r)
	return b
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
// Accepts localhost, 127.0.0.1, 0.0.0.0, and [::1] as equivalent.
func (a *Agent) validateURL(rawURL string) (string, error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return "", fmt.Errorf("invalid URL: %w", err)
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return "", fmt.Errorf("unsupported URL scheme: %s", u.Scheme)
	}
	if !hostsMatch(u.Host, a.config.ServerURL.Host) {
		return "", fmt.Errorf("untrusted URL host: %s (must match configured GoCD server %s)", u.Host, a.config.ServerURL.Host)
	}
	// Reconstruct securely using trusted host and scheme
	target := *a.config.ServerURL
	target.Path = u.Path
	target.RawQuery = u.RawQuery
	target.Fragment = u.Fragment
	return target.String(), nil
}

// hostsMatch returns true if both hosts are equivalent — treating loopback addresses as the same.
func hostsMatch(host1, host2 string) bool {
	if host1 == host2 {
		return true
	}
	return isLoopback(host1) && isLoopback(host2)
}

// isLoopback returns true for localhost, 127.0.0.1, [::1], 0.0.0.0 and variants.
func isLoopback(host string) bool {
	// Strip port
	if h, _, err := net.SplitHostPort(host); err == nil {
		host = h
	}
	switch host {
	case "localhost", "127.0.0.1", "::1", "[::1]", "0.0.0.0":
		return true
	}
	return false
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

// cleanupJobDirs removes old job directories keeping at most MaxJobDirs most recent
// and at most MaxJobDirsMB total size. Only cleans dirs under ex_gocd_jobs/.
// Safety: requires at least 3 levels below the work dir (ex_gocd_jobs/pipeline/counter/...)
// before any removal, preventing accidental rm -rf /.
func (a *Agent) cleanupJobDirs() {
	jobsRoot := filepath.Join(a.config.WorkingDir, "ex_gocd_jobs")
	entries, err := os.ReadDir(jobsRoot)
	if err != nil {
		if !os.IsNotExist(err) {
			agentlog.Logger.Warn().Err(err).Str("dir", jobsRoot).Msg("Failed to read jobs directory")
		}
		return
	}

	type dirInfo struct {
		path    string
		modTime time.Time
		size    int64
		depth   int // path components below jobsRoot
	}

	var dirs []dirInfo
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		pipelineDir := filepath.Join(jobsRoot, entry.Name())

		// Walk pipeline/counter/stage/stage_counter/job structure
		_ = filepath.WalkDir(pipelineDir, func(path string, d fs.DirEntry, err error) error {
			if err != nil || !d.IsDir() || path == pipelineDir {
				return nil
			}

			rel, relErr := filepath.Rel(jobsRoot, path)
			if relErr != nil {
				return nil
			}
			depth := len(strings.Split(rel, string(filepath.Separator)))

			// Safety: at least 3 levels deep (pipeline/counter/stage)
			if depth < 3 {
				return nil
			}

			info, statErr := d.Info()
			if statErr != nil {
				return nil
			}

			// Only target leaf job directories (5+ levels: pipeline/counter/stage/stage_counter/job)
			// or 3+ levels with no subdirectories (orphaned leaves from older structure)
			if depth >= 5 || !hasSubdirs(path) {
				size := dirSize(path)
				dirs = append(dirs, dirInfo{
					path:    path,
					modTime: info.ModTime(),
					size:    size,
					depth:   depth,
				})
			}
			return nil
		})
	}

	if len(dirs) == 0 {
		return
	}

	// Sort oldest first
	sort.Slice(dirs, func(i, j int) bool { return dirs[i].modTime.Before(dirs[j].modTime) })

	// Compute current state
	totalDirs := len(dirs)
	var totalSize int64
	for _, d := range dirs {
		totalSize += d.size
	}

	// Determine which dirs to remove (oldest first) until within limits
	toRemove := 0
	keepSize := totalSize
	for toRemove < len(dirs) {
		if totalDirs-toRemove <= a.config.MaxJobDirs && keepSize <= a.config.MaxJobDirsMB*1024*1024 {
			break
		}
		keepSize -= dirs[toRemove].size
		toRemove++
	}

	if toRemove == 0 {
		return
	}

	removed := 0
	for i := 0; i < toRemove; i++ {
		path := dirs[i].path
		// Final safety: verify still at least 3 levels deep
		rel, _ := filepath.Rel(jobsRoot, path)
		if len(strings.Split(rel, string(filepath.Separator))) < 3 {
			agentlog.Logger.Warn().Str("path", path).Msg("Skipping removal: insufficient path depth")
			continue
		}
		if err := os.RemoveAll(path); err != nil {
			agentlog.Logger.Warn().Err(err).Str("path", path).Msg("Failed to remove job directory")
		} else {
			removed++
		}
	}
	if removed > 0 {
		agentlog.Logger.Info().
			Int("removed", removed).
			Int("remaining", totalDirs-removed).
			Int64("freed_mb", (totalSize-keepSize)/(1024*1024)).
			Msg("Circular cleanup: removed old job directories")
	}
}

func (a *Agent) periodicCleanup(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			a.cleanupJobDirs()
		}
	}
}

func hasSubdirs(path string) bool {
	entries, err := os.ReadDir(path)
	if err != nil {
		return false
	}
	for _, e := range entries {
		if e.IsDir() {
			return true
		}
	}
	return false
}

func dirSize(path string) int64 {
	var size int64
	_ = filepath.WalkDir(path, func(_ string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		info, statErr := d.Info()
		if statErr == nil {
			size += info.Size()
		}
		return nil
	})
	return size
}

// cleanupStaleBuildDirs is DEPRECATED — replaced by cleanupJobDirs with circular limits.
