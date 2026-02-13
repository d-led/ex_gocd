// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package agent

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"

	"github.com/d-led/ex_gocd/agent/internal/config"
	"github.com/d-led/ex_gocd/agent/internal/console"
	"github.com/d-led/ex_gocd/agent/internal/registration"
	"github.com/d-led/ex_gocd/agent/internal/remoting"
	"github.com/d-led/ex_gocd/agent/internal/websocket"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
	"github.com/google/uuid"
)

// Agent represents the GoCD agent
type Agent struct {
	config     *config.Config
	registrar  *registration.Registrar
	conn       *websocket.Connection
	httpClient *http.Client
	cookie     string
	state      string
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

// Start runs the agent lifecycle:
// 1. Register with server
// 2. By default use remoting API (get_cookie, get_work polling) for compatibility with real GoCD
// 3. If AGENT_USE_WEBSOCKET=true, use WebSocket instead (new feature, e.g. for ex_gocd)
func (a *Agent) Start(ctx context.Context) error {
	log.Printf("Starting agent %s", a.config.UUID)
	log.Printf("Server: %s", a.config.ServerURL.String())
	log.Printf("Working directory: %s", a.config.WorkingDir)
	if a.config.UseWebSocket {
		log.Println("Mode: WebSocket (AGENT_USE_WEBSOCKET=true)")
	} else {
		log.Println("Mode: remoting API (polling) — compatible with real GoCD")
	}

	// Register with server
	log.Println("Registering with server...")
	if err := a.registrar.Register(); err != nil {
		return fmt.Errorf("registration failed: %w", err)
	}
	log.Println("Registration successful")

	tlsConfig, err := a.registrar.CreateTLSConfig()
	if err != nil {
		return fmt.Errorf("failed to create TLS config: %w", err)
	}

	if a.config.UseWebSocket {
		return a.runWithConnection(ctx, tlsConfig)
	}
	return a.runWithRemoting(ctx, tlsConfig)
}

// runWithRemoting runs the polling loop: get_cookie, then get_work periodically and execute builds.
func (a *Agent) runWithRemoting(ctx context.Context, tlsConfig *tls.Config) error {
	a.httpClient = &http.Client{
		Transport: &http.Transport{TLSClientConfig: tlsConfig},
		Timeout:   30 * time.Second,
	}
	remotingClient, err := remoting.NewClient(a.config, a.httpClient)
	if err != nil {
		return fmt.Errorf("remoting client: %w", err)
	}
	runtimeInfo := a.getRuntimeInfo()
	if a.cookie == "" {
		cookie, err := remotingClient.GetCookie(runtimeInfo)
		if err != nil {
			return fmt.Errorf("get_cookie: %w", err)
		}
		a.cookie = cookie
		runtimeInfo.Cookie = cookie
		log.Println("Got cookie from server (remoting)")
	}
	workTicker := time.NewTicker(a.config.WorkPollInterval)
	defer workTicker.Stop()
	pingTicker := time.NewTicker(a.config.HeartbeatInterval)
	defer pingTicker.Stop()
	log.Println("Polling for work (remoting)...")
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-pingTicker.C:
			if _, err := remotingClient.Ping(runtimeInfo); err != nil {
				log.Printf("ping error: %v", err)
			}
		case <-workTicker.C:
			if a.state != "Idle" {
				continue
			}
			work, err := remotingClient.GetWork(runtimeInfo)
			if err != nil {
				log.Printf("get_work error: %v", err)
				continue
			}
			if work == nil {
				continue
			}
			build := work.ToBuild(a.config.ServerURL.String())
			if build == nil || build.BuildCommand == nil {
				continue
			}
			jobID := work.Assignment.JobIdentifier
			sendRemoting := func(msg *protocol.Message) {
				a.sendRemotingReport(remotingClient, jobID, msg)
			}
			a.handleBuildWithSend(build, sendRemoting)
		}
	}
}

func (a *Agent) sendRemotingReport(c *remoting.Client, jobID *remoting.JobIdentifier, msg *protocol.Message) {
	if jobID == nil {
		return
	}
	r := msg.Report()
	if r == nil {
		return
	}
	ri := r.AgentRuntimeInfo
	if ri == nil {
		ri = a.getRuntimeInfo()
	}
	switch msg.Action {
	case protocol.ReportCurrentStatusAction:
		_ = c.ReportCurrentStatus(ri, jobID, r.JobState)
	case protocol.ReportCompletingAction:
		_ = c.ReportCompleting(ri, jobID, r.Result)
	case protocol.ReportCompletedAction:
		_ = c.ReportCompleted(ri, jobID, r.Result)
	}
}

// runWithConnection establishes WebSocket and runs until disconnection
func (a *Agent) runWithConnection(ctx context.Context, tlsConfig *tls.Config) error {
	// HTTP client for console/artifact uploads (same TLS as WebSocket)
	a.httpClient = &http.Client{
		Transport: &http.Transport{TLSClientConfig: tlsConfig},
		Timeout:   30 * time.Second,
	}
	// Connect WebSocket
	log.Println("Connecting to server via WebSocket...")
	conn, err := websocket.Connect(ctx, a.config, tlsConfig)
	if err != nil {
		return fmt.Errorf("WebSocket connection failed: %w", err)
	}
	defer conn.Close()
	a.conn = conn
	log.Println("WebSocket connected")
	
	// Start ping ticker
	pingTicker := time.NewTicker(a.config.HeartbeatInterval)
	defer pingTicker.Stop()
	
	// Send initial ping
	a.sendPing()
	
	// Main event loop
	for {
		select {
		case <-ctx.Done():
			return nil
			
		case <-pingTicker.C:
			a.sendPing()
			
		case msg, ok := <-conn.Receive():
			if !ok {
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
	log.Printf("Received message: %s", msg.Action)
	
	switch msg.Action {
	case protocol.SetCookieAction:
		cookie := msg.DataString()
		a.cookie = cookie
		a.conn.SetCookie(cookie)
		log.Printf("Cookie set: %s", cookie)
		
	case protocol.ReregisterAction:
		log.Println("Server requested re-registration")
		// Clean up and exit - supervisor will restart
		return fmt.Errorf("re-registration requested")
		
	case protocol.CancelBuildAction:
		log.Println("Build cancellation requested")
		// TODO: Cancel running build
		
	case protocol.BuildAction:
		build := msg.DataBuild()
		log.Printf("Build assigned: %s", build.BuildId)
		send := func(m *protocol.Message) { a.conn.Send(m) }
		a.handleBuildWithSend(build, send)
		
	default:
		log.Printf("Unknown message action: %s", msg.Action)
	}
	
	return nil
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

// handleBuildWithSend executes a build with a given send function for status reports (WebSocket or remoting).
func (a *Agent) handleBuildWithSend(build *protocol.Build, send func(*protocol.Message)) {
	a.state = "Building"
	defer func() { a.state = "Idle" }()

	reportStatus := func(buildID, jobState, result string) {
		r := &protocol.Report{
			BuildId:          buildID,
			JobState:         jobState,
			Result:           result,
			AgentRuntimeInfo: a.getRuntimeInfo(),
		}
		var msg *protocol.Message
		switch jobState {
		case "Completed":
			msg = protocol.ReportCompletedMessage(r)
		case "Completing":
			msg = protocol.ReportCompletingMessage(r)
		default:
			msg = protocol.ReportCurrentStatusMessage(r)
		}
		send(msg)
	}

	log.Printf("Executing build: %s", build.BuildId)
	if build.BuildCommand == nil {
		log.Printf("Build %s has no command", build.BuildId)
		reportStatus(build.BuildId, "Completed", "Passed")
		return
	}

	rootDir := filepath.Join(a.config.WorkingDir, sanitizeBuildDir(build.BuildId))
	if err := os.MkdirAll(rootDir, 0755); err != nil {
		log.Printf("Failed to create build dir: %v", err)
		reportStatus(build.BuildId, "Completed", "Failed")
		return
	}

	con, err := console.NewWriter(a.httpClient, a.config.ServerURL, build.ConsoleUrl)
	if err != nil {
		log.Printf("Failed to create console writer: %v", err)
		reportStatus(build.BuildId, "Completed", "Failed")
		return
	}

	getReport := func(buildID, jobState, result string) *protocol.Report {
		return &protocol.Report{
			BuildId:          buildID,
			JobState:         jobState,
			Result:           result,
			AgentRuntimeInfo: a.getRuntimeInfo(),
		}
	}
	session := NewBuildSessionWithConsole(build.BuildId, build.BuildCommand, rootDir, con, send, getReport, nil)
	session.Run()
}

func sanitizeBuildDir(s string) string {
	s = strings.ReplaceAll(s, "/", "_")
	s = strings.ReplaceAll(s, "\\", "_")
	if s == "" {
		return "default"
	}
	return s
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
