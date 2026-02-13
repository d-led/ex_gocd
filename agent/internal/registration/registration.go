// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package registration

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/d-led/ex_gocd/agent/internal/config"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

// Registrar handles agent registration with the server
type Registrar struct {
	config     *config.Config
	httpClient *http.Client
}

// New creates a new Registrar
func New(cfg *config.Config) *Registrar {
	return &Registrar{
		config: cfg,
	}
}

// Register performs the full registration flow with retry logic:
// 1. Read GoCD server CA certificate
// 2. Request token from server
// 3. Register with token and get agent certificates (retries if pending approval)
func (r *Registrar) Register() error {
	// Read server CA certificate
	if err := r.readServerCACert(); err != nil {
		return fmt.Errorf("failed to read server CA: %w", err)
	}

	// Create HTTP client with CA validation
	client, err := r.createHTTPClient(false)
	if err != nil {
		return fmt.Errorf("failed to create HTTP client: %w", err)
	}
	r.httpClient = client

	// Request token if we don't have one
	if err := r.requestToken(); err != nil {
		return fmt.Errorf("failed to request token: %w", err)
	}

	// Register and get certificates with retry for pending approval
	if err := r.registerWithRetry(); err != nil {
		return fmt.Errorf("failed to register: %w", err)
	}

	return nil
}

// readServerCACert downloads the server CA certificate
func (r *Registrar) readServerCACert() error {
	caFile := r.config.GoServerCAFile()

	// Skip if CA file already exists
	if _, err := os.Stat(caFile); err == nil {
		return nil
	}

	serverURL := r.config.ServerURL

	// Only get CA cert if using HTTPS
	if serverURL.Scheme != "https" {
		// For HTTP servers, create a dummy CA file for consistency
		if err := os.MkdirAll(filepath.Dir(caFile), 0755); err != nil {
			return err
		}
		return os.WriteFile(caFile, []byte("# Not using TLS\n"), 0644)
	}

	// Create insecure client to download CA cert
	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
			},
		},
	}

	caCertURL := serverURL.String() + "/admin/agent/root_certificate"

	resp, err := client.Get(caCertURL)
	if err != nil {
		return fmt.Errorf("failed to download CA cert from %s: %w", caCertURL, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to download CA cert: status %d", resp.StatusCode)
	}

	caCert, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	// Ensure config directory exists
	if err := os.MkdirAll(filepath.Dir(caFile), 0755); err != nil {
		return err
	}

	return os.WriteFile(caFile, caCert, 0644)
}

// requestToken requests an agent token from the server, or uses a shared demo cookie when set.
func (r *Registrar) requestToken() error {
	tokenFile := r.config.AgentTokenFile()

	// Demo/dev: use shared cookie so phx.server + start-agent and docker-compose always match
	if demo := os.Getenv("EX_GOCD_DEMO_COOKIE"); demo != "" {
		token := strings.TrimSpace(demo)
		if err := os.MkdirAll(filepath.Dir(tokenFile), 0755); err != nil {
			return err
		}
		if err := os.WriteFile(tokenFile, []byte(token), 0600); err != nil {
			return err
		}
		log.Println("Using shared demo cookie from EX_GOCD_DEMO_COOKIE")
		return nil
	}
	if demo := os.Getenv("AGENT_DEMO_COOKIE"); demo != "" {
		token := strings.TrimSpace(demo)
		if err := os.MkdirAll(filepath.Dir(tokenFile), 0755); err != nil {
			return err
		}
		if err := os.WriteFile(tokenFile, []byte(token), 0600); err != nil {
			return err
		}
		log.Println("Using shared demo cookie from AGENT_DEMO_COOKIE")
		return nil
	}

	// Skip if token file already exists
	if _, err := os.Stat(tokenFile); err == nil {
		return nil
	}

	tokenURL := r.config.TokenURL()

	resp, err := r.httpClient.Get(tokenURL)
	if err != nil {
		return fmt.Errorf("failed to request token from %s: %w", tokenURL, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to request token: status %d", resp.StatusCode)
	}

	token, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	return os.WriteFile(tokenFile, token, 0600)
}

// registerAndGetCerts registers with the server and downloads agent certificates
func (r *Registrar) registerAndGetCerts() error {
	// For HTTP servers, certificates are not used or returned
	if r.config.ServerURL.Scheme == "http" {
		log.Println("HTTP server - skipping certificate retrieval")
		return r.registerHTTP()
	}

	// HTTPS flow - get certificates
	privateKeyFile := r.config.AgentPrivateKeyFile()
	certFile := r.config.AgentCertFile()

	// Skip if we already have certificates
	_, keyErr := os.Stat(privateKeyFile)
	_, certErr := os.Stat(certFile)
	if keyErr == nil && certErr == nil {
		log.Println("Agent already has certificates")
		return nil
	}

	return r.registerAndDownloadCerts()
}

// registerHTTP performs basic registration for HTTP servers (no certificates)
func (r *Registrar) registerHTTP() error {
	// Read token
	token, err := os.ReadFile(r.config.AgentTokenFile())
	if err != nil {
		return fmt.Errorf("failed to read token: %w", err)
	}

	// Prepare registration form data
	formData := r.registrationData()
	formData.Set("token", string(token))

	// Register with server
	registrationURL := r.config.RegistrationURL()
	resp, err := r.httpClient.PostForm(registrationURL, formData)
	if err != nil {
		return fmt.Errorf("failed to POST registration to %s: %w", registrationURL, err)
	}
	defer resp.Body.Close()

	// For HTTP, we might get an empty 200 response which is OK
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("registration failed: status %d, body: %s", resp.StatusCode, string(body))
	}

	log.Println("HTTP registration completed")
	return nil
}

// registerAndDownloadCerts performs HTTPS registration and downloads certificates
func (r *Registrar) registerAndDownloadCerts() error {
	// Read token
	token, err := os.ReadFile(r.config.AgentTokenFile())
	if err != nil {
		return fmt.Errorf("failed to read token: %w", err)
	}

	// Prepare registration form data
	formData := r.registrationData()
	formData.Set("token", string(token))

	// Register with server
	registrationURL := r.config.RegistrationURL()

	resp, err := r.httpClient.PostForm(registrationURL, formData)
	if err != nil {
		return fmt.Errorf("failed to POST registration to %s: %w", registrationURL, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("registration failed: status %d, body: %s", resp.StatusCode, string(body))
	}

	// Read response body
	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response body: %w", err)
	}

	// Check if response is empty (agent pending approval)
	if len(bodyBytes) == 0 {
		return fmt.Errorf("registration pending: agent may need approval on server (empty response)")
	}

	// Parse registration response
	var registration protocol.Registration
	if err := json.Unmarshal(bodyBytes, &registration); err != nil {
		return fmt.Errorf("failed to decode registration response (got %d bytes): %w", len(bodyBytes), err)
	}

	if registration.AgentCertificate == "" {
		return fmt.Errorf("registration failed: empty certificate (agent may need approval on server)")
	}

	// Save private key and certificate
	privateKeyFile := r.config.AgentPrivateKeyFile()
	certFile := r.config.AgentCertFile()

	if err := os.WriteFile(privateKeyFile, []byte(registration.AgentPrivateKey), 0600); err != nil {
		return fmt.Errorf("failed to write private key: %w", err)
	}

	if err := os.WriteFile(certFile, []byte(registration.AgentCertificate), 0600); err != nil {
		return fmt.Errorf("failed to write certificate: %w", err)
	}

	log.Println("HTTPS registration completed with certificates")
	return nil
}

// registrationData prepares the form data for registration
func (r *Registrar) registrationData() url.Values {
	cfg := r.config

	return url.Values{
		"hostname":                      {cfg.Hostname},
		"uuid":                          {cfg.UUID},
		"ipAddress":                     {cfg.IPAddress},
		"location":                      {cfg.WorkingDir},
		"operatingSystem":               {runtime.GOOS},
		"usablespace":                   {strconv.FormatInt(usableSpace(), 10)},
		"agentAutoRegisterKey":          {cfg.AutoRegisterKey},
		"agentAutoRegisterResources":    {cfg.Resources},
		"agentAutoRegisterEnvironments": {cfg.Environments},
		"agentAutoRegisterHostname":     {cfg.Hostname},
		"elasticAgentId":                {cfg.ElasticAgentID},
		"elasticPluginId":               {cfg.ElasticPluginID},
		"supportsBuildCommandProtocol":  {"true"},
	}
}

// createHTTPClient creates an HTTP client with TLS configuration
func (r *Registrar) createHTTPClient(withClientCert bool) (*http.Client, error) {
	tlsConfig, err := r.createTLSConfig(withClientCert)
	if err != nil {
		return nil, err
	}

	return &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: tlsConfig,
		},
	}, nil
}

// createTLSConfig creates TLS configuration for client
func (r *Registrar) createTLSConfig(withClientCert bool) (*tls.Config, error) {
	// If using HTTP (not HTTPS), return nil - no TLS needed
	if r.config.ServerURL.Scheme != "https" && r.config.ServerURL.Scheme != "wss" {
		return nil, nil
	}

	// Load server CA certificate
	caCert, err := os.ReadFile(r.config.GoServerCAFile())
	if err != nil {
		return nil, fmt.Errorf("failed to read CA cert: %w", err)
	}

	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(caCert) {
		return nil, fmt.Errorf("failed to parse CA certificate")
	}

	// Extract server DN for verification
	serverName, err := extractServerDN(r.config.GoServerCAFile())
	if err != nil {
		return nil, err
	}

	tlsConfig := &tls.Config{
		RootCAs:    roots,
		ServerName: serverName,
	}

	// Add client certificate if requested
	if withClientCert {
		cert, err := tls.LoadX509KeyPair(
			r.config.AgentCertFile(),
			r.config.AgentPrivateKeyFile(),
		)
		if err != nil {
			return nil, fmt.Errorf("failed to load client cert: %w", err)
		}
		tlsConfig.Certificates = []tls.Certificate{cert}
	}

	return tlsConfig, nil
}

// extractServerDN extracts the server DN from certificate
func extractServerDN(certFile string) (string, error) {
	pemData, err := os.ReadFile(certFile)
	if err != nil {
		return "", err
	}

	block, _ := pem.Decode(pemData)
	if block == nil {
		return "", fmt.Errorf("failed to decode PEM certificate")
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return "", err
	}

	return cert.Subject.CommonName, nil
}

// usableSpace returns the available disk space in bytes
func usableSpace() int64 {
	// Simplified - return 10GB
	// In production, use syscall.Statfs or similar
	return 10 * 1024 * 1024 * 1024
}

// registerWithRetry attempts registration with exponential backoff for approval
func (r *Registrar) registerWithRetry() error {
	// For HTTP servers, empty responses are normal - no retry needed
	if r.config.ServerURL.Scheme == "http" {
		return r.registerAndGetCerts()
	}

	// For HTTPS servers, retry if agent approval is pending
	maxRetries := 5
	baseDelay := 2 * time.Second

	for attempt := 0; attempt < maxRetries; attempt++ {
		err := r.registerAndGetCerts()
		if err == nil {
			return nil
		}

		// Check if it's a pending approval error
		if strings.Contains(err.Error(), "pending") || strings.Contains(err.Error(), "empty") {
			if attempt < maxRetries-1 {
				delay := baseDelay * time.Duration(1<<uint(attempt)) // Exponential backoff
				log.Printf("Agent pending approval, retrying in %v (attempt %d/%d)...", delay, attempt+1, maxRetries)
				time.Sleep(delay)
				continue
			}
		}

		return err
	}

	return fmt.Errorf("registration failed after %d attempts", maxRetries)
}

// CreateTLSConfig creates a TLS config for WebSocket connection
func (r *Registrar) CreateTLSConfig() (*tls.Config, error) {
	return r.createTLSConfig(true)
}
