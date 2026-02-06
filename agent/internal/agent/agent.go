// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package agent

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"os"
	"runtime"
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
	config     *config.Config
	registrar  *registration.Registrar
	conn       *websocket.Connection
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
		// TODO: Execute build
		a.handleBuild(build)
		
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

// handleBuild executes a build
func (a *Agent) handleBuild(build *protocol.Build) {
	a.state = "Building"
	defer func() { a.state = "Idle" }()
	
	// TODO: Implement full build execution
	// For now, just report completion
	
	log.Printf("Executing build: %s", build.BuildId)
	
	// Report building
	a.reportStatus(build.BuildId, "Building", "")
	
	// Simulate work
	time.Sleep(2 * time.Second)
	
	// Report completion
	a.reportStatus(build.BuildId, "Completed", "Passed")
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
