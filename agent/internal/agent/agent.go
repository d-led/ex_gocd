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
	"log"
	"mime/multipart"
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
	switch cmd.Name {
	case "uploadArtifact":
		return a.runUploadArtifact(ctx, build, cmd)
	case "fetchArtifact":
		return a.runFetchArtifact(ctx, build, cmd)
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

func (a *Agent) httpClient() (*http.Client, error) {
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
	log.Printf("Executing uploadArtifact: Src=%q, Dest=%q", cmd.Src, cmd.Dest)
	dir := a.config.WorkingDir
	if cmd.WorkingDir != "" {
		dir = cmd.WorkingDir
	}
	absDir, err := filepath.Abs(dir)
	if err != nil {
		return fmt.Errorf("working dir: %w", err)
	}

	srcPath := cmd.Src
	if !filepath.IsAbs(srcPath) {
		srcPath = filepath.Join(absDir, srcPath)
	}

	if _, err := os.Stat(srcPath); err != nil {
		return fmt.Errorf("artifact source path %q does not exist: %w", srcPath, err)
	}

	return a.uploadArtifact(ctx, build, cmd, srcPath)
}

func (a *Agent) uploadArtifact(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand, srcPath string) error {
	msg := fmt.Sprintf("Uploading artifact %s to %s on server...\n", cmd.Src, cmd.Dest)
	_ = postConsole(build.ConsoleUrl, time.Now().Format("15:04:05.000")+" "+msg)

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

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, uploadURL, body)
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
	_ = postConsole(build.ConsoleUrl, time.Now().Format("15:04:05.000")+" "+successMsg)
	return nil
}

func (a *Agent) runFetchArtifact(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand) error {
	log.Printf("Executing fetchArtifact: Src=%q, Dest=%q", cmd.Src, cmd.Dest)
	dir := a.config.WorkingDir
	if cmd.WorkingDir != "" {
		dir = cmd.WorkingDir
	}
	absDir, err := filepath.Abs(dir)
	if err != nil {
		return fmt.Errorf("working dir: %w", err)
	}

	destPath := cmd.Dest
	if !filepath.IsAbs(destPath) {
		destPath = filepath.Join(absDir, destPath)
	}

	return a.fetchArtifact(ctx, build, cmd, destPath)
}

func (a *Agent) fetchArtifact(ctx context.Context, build *protocol.Build, cmd *protocol.BuildCommand, destPath string) error {
	msg := fmt.Sprintf("Fetching artifact %s to %s...\n", cmd.Src, cmd.Dest)
	_ = postConsole(build.ConsoleUrl, time.Now().Format("15:04:05.000")+" "+msg)

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

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, downloadURL, nil)
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
	isZip := contentType == "application/zip" || strings.HasSuffix(downloadURL, ".zip")

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
	_ = postConsole(build.ConsoleUrl, time.Now().Format("15:04:05.000")+" "+successMsg)
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
		if filepath.IsAbs(cleanedPath) || strings.HasPrefix(cleanedPath, "..") {
			return fmt.Errorf("illegal file path in zip (Zip Slip detected): %s", f.Name)
		}

		targetPath := filepath.Join(destDir, cleanedPath)
		if !strings.HasPrefix(targetPath, destDir+string(filepath.Separator)) && targetPath != destDir {
			return fmt.Errorf("illegal file path in zip (Zip Slip boundary escape): %s", f.Name)
		}

		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(targetPath, 0755); err != nil {
				return err
			}
			continue
		}

		if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
			return err
		}

		outFile, err := os.OpenFile(targetPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
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
