// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package config

import (
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// Config holds agent configuration following 12-factor app principles
type Config struct {
	// Server connection
	ServerURL *url.URL
	
	// Working directories
	WorkingDir string
	WorkDir   string
	ConfigDir string
	
	// Agent identity
	Hostname  string
	IPAddress string
	UUID      string
	
	// Auto-registration
	AutoRegisterKey         string
	Resources               string
	Environments            string
	ElasticAgentID          string
	ElasticPluginID         string
	
	// Polling intervals
	HeartbeatInterval time.Duration
	WorkPollInterval  time.Duration
}

// Load creates a Config from environment variables with sensible defaults
// Uses viper for 12-factor app configuration with AGENT_ prefix
func Load() (*Config, error) {
	// Setup viper with AGENT_ prefix for environment variables
	setupViper()
	
	serverURLStr := viper.GetString("server.url")
	serverURL, err := url.Parse(serverURLStr)
	if err != nil {
		return nil, fmt.Errorf("invalid server URL: %w", err)
	}
	
	workDir := viper.GetString("work.dir")
	
	cfg := &Config{
		ServerURL:         serverURL,
		WorkDir:           workDir,
		WorkingDir:        workDir,
		HeartbeatInterval: viper.GetDuration("heartbeat.interval"),
		WorkPollInterval:  viper.GetDuration("work.poll.interval"),
		AutoRegisterKey:   viper.GetString("auto.register.key"),
		Resources:         viper.GetString("auto.register.resources"),
		Environments:      viper.GetString("auto.register.environments"),
		ElasticAgentID:    viper.GetString("auto.register.elastic.agent.id"),
		ElasticPluginID:   viper.GetString("auto.register.elastic.plugin.id"),
	}
	
	// Derive ConfigDir from WorkDir
	cfg.ConfigDir = filepath.Join(cfg.WorkDir, "config")
	
	// Ensure directories exist
	if err := os.MkdirAll(cfg.WorkDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create work directory: %w", err)
	}
	if err := os.MkdirAll(cfg.ConfigDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create config directory: %w", err)
	}
	
	// Detect hostname and IP
	cfg.Hostname, err = os.Hostname()
	if err != nil {
		return nil, fmt.Errorf("failed to get hostname: %w", err)
	}
	
	cfg.IPAddress, err = detectIPAddress()
	if err != nil {
		return nil, fmt.Errorf("failed to detect IP address: %w", err)
	}
	
	return cfg, nil
}

// setupViper configures viper with AGENT_ prefix and defaults
func setupViper() {
	// Set environment variable prefix (AGENT_)
	viper.SetEnvPrefix("AGENT")
	
	// Replace dots and dashes with underscores in env var names
	// e.g., "server.url" becomes "AGENT_SERVER_URL"
	replacer := strings.NewReplacer(".", "_", "-", "_")
	viper.SetEnvKeyReplacer(replacer)
	
	// Automatically read environment variables
	viper.AutomaticEnv()
	
	// Set default values following 12-factor app principles
	viper.SetDefault("server.url", "http://localhost:8153/go")
	viper.SetDefault("work.dir", "./work")
	viper.SetDefault("heartbeat.interval", 10*time.Second)
	viper.SetDefault("work.poll.interval", 5*time.Second)
	viper.SetDefault("auto.register.key", "")
	viper.SetDefault("auto.register.resources", "")
	viper.SetDefault("auto.register.environments", "")
	viper.SetDefault("auto.register.elastic.agent.id", "")
	viper.SetDefault("auto.register.elastic.plugin.id", "")
}

// UUIDFile returns path to the agent UUID file
func (c *Config) UUIDFile() string {
	return filepath.Join(c.ConfigDir, "agent.uuid")
}

// RegistrationURL returns the full URL for agent registration (form-based)
func (c *Config) RegistrationURL() string {
	u := *c.ServerURL
	u.Path = filepath.Join(u.Path, "admin/agent")
	return u.String()
}

// TokenURL returns the URL for requesting agent token
func (c *Config) TokenURL() string {
	u := *c.ServerURL
	u.Path = filepath.Join(u.Path, "admin/agent/token")
	u.RawQuery = fmt.Sprintf("uuid=%s", c.UUID)
	return u.String()
}

// WebSocketURL returns the WebSocket URL for agent communication
func (c *Config) WebSocketURL() string {
	u := *c.ServerURL
	if u.Scheme == "https" {
		u.Scheme = "wss"
	} else {
		u.Scheme = "ws"
	}
	u.Path = filepath.Join(u.Path, "agent-websocket")
	return u.String()
}

// GoServerCAFile returns path to server CA certificate
func (c *Config) GoServerCAFile() string {
	return filepath.Join(c.ConfigDir, "go-server-ca.pem")
}

// AgentPrivateKeyFile returns path to agent private key
func (c *Config) AgentPrivateKeyFile() string {
	return filepath.Join(c.ConfigDir, "agent-private-key.pem")
}

// AgentCertFile returns path to agent certificate
func (c *Config) AgentCertFile() string {
	return filepath.Join(c.ConfigDir, "agent-cert.pem")
}

// AgentTokenFile returns path to agent token
func (c *Config) AgentTokenFile() string {
	return filepath.Join(c.ConfigDir, "token")
}

// detectIPAddress finds the first non-loopback IP address
func detectIPAddress() (string, error) {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return "", err
	}
	
	for _, addr := range addrs {
		if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			if ipnet.IP.To4() != nil {
				return ipnet.IP.String(), nil
			}
		}
	}
	
	return "127.0.0.1", nil
}
