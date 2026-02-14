// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package agent

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/d-led/ex_gocd/agent/internal/config"
	"github.com/d-led/ex_gocd/agent/internal/registration"
	"github.com/d-led/ex_gocd/agent/internal/websocket"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
	"github.com/google/uuid"
)

// Agent represents the GoCD agent
type Agent struct {
	config    *config.Config
	registrar *registration.Registrar
	conn      *websocket.Connection
	cookie    string
	state     string

	// Current build cancellation: guarded by buildMu
	buildMu       sync.Mutex
	currentBuild  string             // buildId of running build, or ""
	cancelBuildFn context.CancelFunc  // call to cancel current build
}

// New creates a new Agent
func New(cfg *config.Config) (*Agent, error) {
	// Load or generate UUID
	if err := loadOrGenerateUUID(cfg); err != nil {
		return nil, err
	}

	return &Agent{
		config:    cfg,
		registrar: registration.New(cfg),
		state:     "Idle",
	}, nil
}

// Start runs the agent lifecycle with automatic reconnection:
// 1. Register with server
// 2. Connect WebSocket (with reconnection)
// 3. Send ping heartbeats
// 4. Process incoming messages
func (a *Agent) Start(ctx context.Context) error {
	log.Printf("Starting agent %s", a.config.UUID)
	log.Printf("Server: %s", a.config.ServerURL.String())
	log.Printf("Working directory: %s", a.config.WorkingDir)

	// Register with server
	log.Println("Registering with server...")
	if err := a.registrar.Register(); err != nil {
		return fmt.Errorf("registration failed: %w", err)
	}
	log.Println("Registration successful")

	// Create TLS config for WebSocket
	tlsConfig, err := a.registrar.CreateTLSConfig()
	if err != nil {
		return fmt.Errorf("failed to create TLS config: %w", err)
	}

	// Main reconnection loop
	retryDelay := 2 * time.Second
	maxRetryDelay := 60 * time.Second

	for {
		select {
		case <-ctx.Done():
			log.Println("Agent shutting down...")
			return nil
		default:
		}

		// Try to connect and run
		err := a.runWithConnection(ctx, tlsConfig)
		if err == nil {
			return nil // Clean shutdown
		}

		// Check if context was cancelled
		if ctx.Err() != nil {
			log.Println("Agent shutting down...")
			return nil
		}

		// Log error and retry with backoff
		log.Printf("Connection lost: %v", err)
		log.Printf("Reconnecting in %v...", retryDelay)

		select {
		case <-time.After(retryDelay):
			// Exponential backoff with max
			retryDelay = retryDelay * 2
			if retryDelay > maxRetryDelay {
				retryDelay = maxRetryDelay
			}
		case <-ctx.Done():
			log.Println("Agent shutting down...")
			return nil
		}
	}
}

// runWithConnection establishes WebSocket and runs until disconnection
func (a *Agent) runWithConnection(ctx context.Context, tlsConfig *tls.Config) error {
	// Connect WebSocket
	log.Println("Connecting to server via WebSocket...")
	conn, err := websocket.Connect(ctx, a.config, tlsConfig)
	if err != nil {
		return fmt.Errorf("WebSocket connection failed: %w", err)
	}
	defer conn.Close()
	a.conn = conn
	log.Println("WebSocket connected")

	// Send join once so the server establishes the channel (do not send ping as join — that caused duplicate-join phx_close)
	a.sendJoin()

	// Start ping ticker for heartbeats
	pingTicker := time.NewTicker(a.config.HeartbeatInterval)
	defer pingTicker.Stop()

	// Main event loop
	for {
		select {
		case <-ctx.Done():
			return nil

		case <-pingTicker.C:
			a.sendPing()

		case msg, ok := <-conn.Receive():
			if !ok {
				log.Printf("WebSocket disconnected (receive channel closed); will reconnect")
				return fmt.Errorf("WebSocket connection closed")
			}
			if err := a.handleMessage(msg); err != nil {
				log.Printf("Error handling message: %v", err)
			}
		}
	}
}

// handleMessage processes incoming messages from server
func (a *Agent) handleMessage(msg *protocol.Message) error {
	switch msg.Action {
	case "phx_reply":
		// Phoenix channel reply to our ping (heartbeat ack). Connection is active.
		log.Printf("Heartbeat acknowledged")

	case "presence_diff":
		// Phoenix Presence broadcast (server tracks who is on the channel). No action needed.
		// Ignore silently to avoid log noise.

	case protocol.SetCookieAction:
		cookie := msg.DataString()
		a.cookie = cookie
		a.conn.SetCookie(cookie)
		preview := cookie
		if len(preview) > 8 {
			preview = preview[:8] + "..."
		}
		log.Printf("Server set agent cookie: %s", preview)

	case protocol.ReregisterAction:
		log.Println("Server requested re-registration")
		// Clean up and exit - supervisor will restart
		return fmt.Errorf("re-registration requested")

	case protocol.CancelBuildAction:
		buildID := msg.BuildIdFromData()
		a.buildMu.Lock()
		cancelFn := a.cancelBuildFn
		matches := a.currentBuild == buildID
		a.buildMu.Unlock()
		if matches && cancelFn != nil {
			log.Printf("Cancelling build: %s", buildID)
			cancelFn()
		} else if buildID != "" {
			log.Printf("Cancel requested for build %s (current build: %q)", buildID, a.currentBuild)
		}

	case protocol.BuildAction:
		build := msg.DataBuild()
		if build != nil {
			log.Printf("Build assigned: %s (%s)", build.BuildId, build.BuildLocatorForDisplay)
			a.handleBuild(build)
		} else {
			log.Printf("Build assigned but failed to parse payload")
		}

	case "phx_close":
		// Server closed the channel (e.g. duplicate join or intentional close); treat as normal close so we reconnect once
		log.Println("Server closed channel (phx_close); will reconnect")
		return fmt.Errorf("channel closed by server")

	default:
		// Unhandled action: likely a bug (new server message we don't support, or typo).
		log.Printf("Unknown message action: %s", msg.Action)
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
	defer func() { a.state = "Idle" }()

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

	log.Printf("Executing build: %s", build.BuildId)
	a.reportStatus(build.BuildId, "Building", "")

	result := "Passed"
	if build.BuildCommand != nil && build.BuildCommand.Command != "" {
		if err := a.runBuildCommand(ctx, build); err != nil {
			if err == context.Canceled {
				result = "Cancelled"
				log.Printf("Build %s was cancelled", build.BuildId)
			} else {
				log.Printf("Build command failed: %v", err)
				result = "Failed"
			}
		}
	} else {
		// No command: minimal success (e.g. server sent build without buildCommand)
		select {
		case <-time.After(500 * time.Millisecond):
		case <-ctx.Done():
			result = "Cancelled"
		}
	}

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
	if len(cmd.SubCommands) > 0 {
		for _, sub := range cmd.SubCommands {
			if err := a.runOneCommand(ctx, build, sub); err != nil {
				return err
			}
		}
		return nil
	}
	return a.runOneCommand(ctx, build, cmd)
}

// runOneCommand runs a single BuildCommand (command + args), streaming output to build.ConsoleUrl when set.
// ctx can be cancelled to kill the process (returns context.Canceled).
func (a *Agent) runOneCommand(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand) error {
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
		return fmt.Errorf("working dir: %w", err)
	}

	c := exec.CommandContext(ctx, path, cmd.Args...)
	c.Dir = absDir

	if build.ConsoleUrl != "" {
		stdoutPipe, _ := c.StdoutPipe()
		stderrPipe, _ := c.StderrPipe()
		c.Stdin = nil
		if err := c.Start(); err != nil {
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
		if err != nil && ctx.Err() == context.Canceled {
			return context.Canceled
		}
		return err
	}

	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	err = c.Run()
	if err != nil && ctx.Err() == context.Canceled {
		return context.Canceled
	}
	return err
}

// streamReaderToConsole reads lines from r, prefixes each with "HH:mm:ss.SSS [prefix]", and POSTs to consoleURL.
func (a *Agent) streamReaderToConsole(consoleURL, linePrefix string, r io.Reader) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(nil, 64*1024)
	for scanner.Scan() {
		line := scanner.Text()
		ts := time.Now().Format("15:04:05.000")
		payload := ts + " " + linePrefix + line + "\n"
		if err := postConsole(consoleURL, payload); err != nil {
			log.Printf("Console POST failed: %v", err)
		}
	}
	if err := scanner.Err(); err != nil {
		payload := time.Now().Format("15:04:05.000") + " [scanner error] " + err.Error() + "\n"
		_ = postConsole(consoleURL, payload)
	}
}

// postConsole POSTs body as text/plain to the given URL.
func postConsole(consoleURL, body string) error {
	if consoleURL == "" {
		return nil
	}
	req, err := http.NewRequest(http.MethodPost, consoleURL, strings.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "text/plain; charset=utf-8")
	resp, err := http.DefaultClient.Do(req)
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

// loadOrGenerateUUID loads existing UUID or generates a new one
func loadOrGenerateUUID(cfg *config.Config) error {
	uuidFile := cfg.UUIDFile()

	// Try to load existing UUID
	if data, err := os.ReadFile(uuidFile); err == nil {
		cfg.UUID = string(data)
		return nil
	}

	// Generate new UUID
	cfg.UUID = uuid.New().String()

	// Save UUID
	if err := os.WriteFile(uuidFile, []byte(cfg.UUID), 0644); err != nil {
		return fmt.Errorf("failed to write UUID file: %w", err)
	}

	return nil
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
