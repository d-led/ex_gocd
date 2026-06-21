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
	"github.com/d-led/ex_gocd/agent/internal/registration"
	"github.com/d-led/ex_gocd/agent/internal/websocket"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
	"github.com/google/uuid"
	"github.com/rs/zerolog"
)

var logger zerolog.Logger

func init() {
	// Dual output: console (human-readable) + JSON file for Fluent Bit → Loki
	logFile := "/tmp/ex_gocd_agent.log"
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		f = nil // fallback: console only
	}

	consoleWriter := zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: time.RFC3339}
	var writers []io.Writer
	writers = append(writers, consoleWriter)
	if f != nil {
		writers = append(writers, f)
	}
	multi := zerolog.MultiLevelWriter(writers...)
	logger = zerolog.New(multi).With().Timestamp().Str("agent", hostname()).Logger()
}

func hostname() string {
	h, _ := os.Hostname()
	return h
}

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
	logger.Info().Msgf("Starting agent %s", a.config.UUID)
	logger.Info().Msgf("Server: %s", a.config.ServerURL.String())
	logger.Info().Msgf("Working directory: %s", a.config.WorkingDir)

	// Register with server
	logger.Info().Msg("Registering with server...")
	if err := a.registrar.Register(); err != nil {
		return fmt.Errorf("registration failed: %w", err)
	}
	logger.Info().Msg("Registration successful")

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
			logger.Info().Msg("Agent shutting down...")
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
			logger.Info().Msg("Agent shutting down...")
			return nil
		}

		// Log error and retry with backoff
		logger.Info().Msgf("Connection lost: %v", err)
		logger.Info().Msgf("Reconnecting in %v...", retryDelay)

		select {
		case <-time.After(retryDelay):
			// Exponential backoff with max
			retryDelay = retryDelay * 2
			if retryDelay > maxRetryDelay {
				retryDelay = maxRetryDelay
			}
		case <-ctx.Done():
			logger.Info().Msg("Agent shutting down...")
			return nil
		}
	}
}

// runWithConnection establishes WebSocket and runs until disconnection
func (a *Agent) runWithConnection(ctx context.Context, tlsConfig *tls.Config) error {
	// Connect WebSocket
	logger.Info().Msg("Connecting to server via WebSocket...")
	conn, err := websocket.Connect(ctx, a.config, tlsConfig)
	if err != nil {
		return fmt.Errorf("WebSocket connection failed: %w", err)
	}
	defer conn.Close()
	a.conn = conn
	logger.Info().Msg("WebSocket connected")

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
				logger.Info().Msgf("WebSocket disconnected (receive channel closed); will reconnect")
				return fmt.Errorf("WebSocket connection closed")
			}
			if err := a.handleMessage(msg); err != nil {
				logger.Info().Msgf("Error handling message: %v", err)
			}
		}
	}
}

// handleMessage processes incoming messages from server
func (a *Agent) handleMessage(msg *protocol.Message) error {
	switch msg.Action {
	case "phx_reply":
		// Phoenix channel reply to our ping (heartbeat ack). Connection is active.
		logger.Info().Msgf("Heartbeat acknowledged")

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
		logger.Info().Msgf("Server set agent cookie: %s", preview)

	case protocol.ReregisterAction:
		logger.Info().Msg("Server requested re-registration")
		// Clean up and exit - supervisor will restart
		return fmt.Errorf("re-registration requested")

	case protocol.CancelBuildAction:
		buildID := msg.BuildIdFromData()
		a.buildMu.Lock()
		cancelFn := a.cancelBuildFn
		matches := a.currentBuild == buildID
		a.buildMu.Unlock()
		if matches && cancelFn != nil {
			logger.Info().Msgf("Cancelling build: %s", buildID)
			cancelFn()
		} else if buildID != "" {
			logger.Info().Msgf("Cancel requested for build %s (current build: %q)", buildID, a.currentBuild)
		}

	case protocol.BuildAction:
		build := msg.DataBuild()
		if build != nil {
			logger.Info().Msgf("Build assigned: %s (%s)", build.BuildId, build.BuildLocatorForDisplay)
			a.handleBuild(build)
		} else {
			logger.Info().Msgf("Build assigned but failed to parse payload")
		}

	case "phx_close":
		// Server closed the channel (e.g. duplicate join or intentional close); treat as normal close so we reconnect once
		logger.Info().Msg("Server closed channel (phx_close); will reconnect")
		return fmt.Errorf("channel closed by server")

	default:
		// Unhandled action: likely a bug (new server message we don't support, or typo).
		logger.Info().Msgf("Unknown message action: %s", msg.Action)
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

	logger.Info().Msgf("Executing build: %s", build.BuildId)
	if build.BuildCommand != nil {
		logger.Info().Msgf("Build command: name=%q, command=%q, subcommands=%d", build.BuildCommand.Name, build.BuildCommand.Command, len(build.BuildCommand.SubCommands))
	}
	a.reportStatus(build.BuildId, "Building", "")

	result := "Passed"
	if build.BuildCommand != nil && (build.BuildCommand.Command != "" || len(build.BuildCommand.SubCommands) > 0) {
		if err := a.runBuildCommand(ctx, build); err != nil {
			if err == context.Canceled {
				result = "Cancelled"
				logger.Info().Msgf("Build %s was cancelled", build.BuildId)
			} else {
				logger.Info().Msgf("Build command failed: %v", err)
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
	switch cmd.Name {
	case "uploadArtifact":
		return a.runUploadArtifact(ctx, build, cmd)
	case "fetchArtifact":
		return a.runFetchArtifact(ctx, build, cmd)
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
			logger.Info().Msgf("Exported env var %s", name)
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
		return fmt.Errorf("working dir: %w", err)
	}

	cleanedPath := filepath.Clean(path)
	resolvedPath, err := exec.LookPath(cleanedPath)
	if err != nil {
		resolvedPath = cleanedPath
	}

	c := exec.CommandContext(ctx, resolvedPath, cmd.Args...)
	c.Dir = absDir

	// Merge environment variables
	c.Env = os.Environ()
	for k, v := range env {
		c.Env = append(c.Env, fmt.Sprintf("%s=%s", k, v))
	}

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
	logger.Info().Msgf("Executing uploadArtifact: Src=%q, Dest=%q", cmd.Src, cmd.Dest)
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
	logger.Info().Msgf("Executing fetchArtifact: Src=%q, Dest=%q", cmd.Src, cmd.Dest)
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
			logger.Info().Msgf("Recovered panic in streamReaderToConsole: %v", r)
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
				logger.Info().Msgf("Console POST failed: %v", err)
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
