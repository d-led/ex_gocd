// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package telemetry

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"os/exec"
	"strings"
	"time"

	agentlog "github.com/d-led/ex_gocd/agent/internal/log"
	coltracepb "go.opentelemetry.io/proto/otlp/collector/trace/v1"
	"google.golang.org/protobuf/proto"
)

// Relay accepts OTLP traces on 0.0.0.0:<random-port> and forwards them
// to the real collector. Works cross-platform: Docker containers reach it
// via the Docker host address; local child processes via 127.0.0.1.
type Relay struct {
	port         int              // bound port
	localEP      string           // "127.0.0.1:<port>"
	dockerHostEP string           // e.g. "172.17.0.1:<port>" or "host.docker.internal:<port>" or ""
	server       *http.Server
	forwardTo    string           // collector host:port
}

// NewRelay creates a relay that forwards to the given collector endpoint.
func NewRelay(collectorEndpoint string) *Relay {
	return &Relay{
		forwardTo: collectorEndpoint,
	}
}

// Start begins listening on 0.0.0.0:0 and returns the bound port.
// Also detects the Docker host address so containers can reach the relay.
func (r *Relay) Start() (port int, err error) {
	ln, err := net.Listen("tcp", "0.0.0.0:0")
	if err != nil {
		return 0, fmt.Errorf("relay listen: %w", err)
	}

	_, portStr, _ := net.SplitHostPort(ln.Addr().String())
	fmt.Sscanf(portStr, "%d", &r.port)

	r.localEP = fmt.Sprintf("127.0.0.1:%d", r.port)
	r.dockerHostEP = detectDockerHost(r.port)

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/traces", r.handleTraces)
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	r.server = &http.Server{
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	go func() {
		agentlog.Logger.Info().
			Int("port", r.port).
			Str("local_ep", r.localEP).
			Str("docker_host_ep", r.dockerHostEP).
			Str("forward_to", r.forwardTo).
			Msg("OTLP relay listening")
		if err := r.server.Serve(ln); err != nil && err != http.ErrServerClosed {
			agentlog.Logger.Warn().Err(err).Msg("OTLP relay serve stopped")
		}
	}()

	return r.port, nil
}

// Endpoint returns the local loopback address (127.0.0.1:<port>).
func (r *Relay) Endpoint() string {
	return r.localEP
}

// DockerHostEndpoint returns the address Docker containers should use to
// reach the relay, or empty if Docker is not detected.
func (r *Relay) DockerHostEndpoint() string {
	return r.dockerHostEP
}

// detectDockerHost figures out what IP:port Docker containers can use to
// reach the host. Cross-platform: works on Linux, Docker Desktop, Colima, WSL.
func detectDockerHost(port int) string {
	// 1. Docker bridge gateway (works everywhere Docker runs)
	if gw := dockerBridgeGateway(); gw != "" {
		return fmt.Sprintf("%s:%d", gw, port)
	}
	// 2. host.docker.internal (Docker Desktop, some Colima configs)
	if ip := resolveHost("host.docker.internal"); ip != "" {
		return fmt.Sprintf("%s:%d", ip, port)
	}
	// 3. host.lima.internal (Colima)
	if ip := resolveHost("host.lima.internal"); ip != "" {
		return fmt.Sprintf("%s:%d", ip, port)
	}
	// 4. First non-loopback IPv4
	if ip := firstNonLoopbackIPv4(); ip != "" {
		return fmt.Sprintf("%s:%d", ip, port)
	}
	return ""
}

func dockerBridgeGateway() string {
	out, err := exec.Command("docker", "network", "inspect", "bridge",
		"--format", "{{range .IPAM.Config}}{{.Gateway}}{{end}}").Output()
	if err != nil {
		return ""
	}
	gw := strings.TrimSpace(string(out))
	if gw != "" && net.ParseIP(gw) != nil {
		return gw
	}
	return ""
}

func resolveHost(hostname string) string {
	ips, err := net.LookupHost(hostname)
	if err != nil || len(ips) == 0 {
		return ""
	}
	return ips[0]
}

func firstNonLoopbackIPv4() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return ""
	}
	for _, iface := range ifaces {
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			if ipnet, ok := addr.(*net.IPNet); ok {
				ip4 := ipnet.IP.To4()
				if ip4 != nil && !ip4.IsLoopback() && !ip4.IsLinkLocalUnicast() {
					return ip4.String()
				}
			}
		}
	}
	return ""
}

// Shutdown gracefully stops the relay.
func (r *Relay) Shutdown(ctx context.Context) error {
	if r.server == nil {
		return nil
	}
	return r.server.Shutdown(ctx)
}

func (r *Relay) handleTraces(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(req.Body)
	if err != nil {
		agentlog.Logger.Warn().Err(err).Msg("OTLP relay read body failed")
		http.Error(w, "read error", http.StatusBadRequest)
		return
	}
	defer req.Body.Close()

	var traceReq coltracepb.ExportTraceServiceRequest
	if err := proto.Unmarshal(body, &traceReq); err != nil {
		agentlog.Logger.Warn().Err(err).Msg("OTLP relay unmarshal failed")
		http.Error(w, "invalid protobuf", http.StatusBadRequest)
		return
	}

	// Forward to real collector
	data, err := proto.Marshal(&traceReq)
	if err != nil {
		http.Error(w, "marshal error", http.StatusInternalServerError)
		return
	}

	ctx, cancel := context.WithTimeout(req.Context(), 10*time.Second)
	defer cancel()

	fwdURL := fmt.Sprintf("http://%s/v1/traces", r.forwardTo)
	fwdReq, err := http.NewRequestWithContext(ctx, http.MethodPost, fwdURL, bytes.NewReader(data))
	if err != nil {
		agentlog.Logger.Warn().Err(err).Str("url", fwdURL).Msg("OTLP relay forward request failed")
		http.Error(w, "forward error", http.StatusInternalServerError)
		return
	}
	fwdReq.Header.Set("Content-Type", "application/x-protobuf")

	resp, err := http.DefaultClient.Do(fwdReq)
	if err != nil {
		agentlog.Logger.Warn().Err(err).Str("url", fwdURL).Msg("OTLP relay forward to collector failed")
		http.Error(w, "collector unreachable", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		errBody, _ := io.ReadAll(resp.Body)
		agentlog.Logger.Warn().Int("status", resp.StatusCode).Str("body", string(errBody)).Msg("OTLP relay collector returned error")
		http.Error(w, "collector error", http.StatusBadGateway)
		return
	}

	w.WriteHeader(http.StatusOK)
}
