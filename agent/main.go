// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/d-led/ex_gocd/agent/cmd"
	"github.com/d-led/ex_gocd/agent/internal/agent"
	"github.com/d-led/ex_gocd/agent/internal/docker"
	agentlog "github.com/d-led/ex_gocd/agent/internal/log"
	"github.com/google/uuid"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

const (
	defaultMaxRestarts  = 5
	defaultRestartDelay = 5 * time.Second
	minSuccessfulRun    = 30 * time.Second
)

func main() {
	maxRestarts := envInt("AGENT_MAX_RESTARTS", defaultMaxRestarts)
	restartDelay := envDuration("AGENT_RESTART_DELAY", defaultRestartDelay)

	agentlog.Logger.Info().
		Int("max_restarts", maxRestarts).
		Dur("restart_delay", restartDelay).
		Msg("gocd-agent starting")

	// ── OTEL service name ───────────────────────────────────────────
	if sn := os.Getenv("AGENT_OTEL_SERVICE_NAME"); sn != "" {
		os.Setenv("OTEL_SERVICE_NAME", sn)
	}

	// Resolve base work dir from env
	baseWorkDir := os.Getenv("AGENT_WORK_DIR")
	if baseWorkDir == "" {
		baseWorkDir = "work"
	}

	// Ensure base work dir exists
	if err := os.MkdirAll(baseWorkDir, 0755); err != nil {
		agentlog.Logger.Error().Str("dir", baseWorkDir).Err(err).Msg("cannot create base work directory")
		fmt.Fprintf(os.Stderr, "gocd-agent: cannot create %s: %v\n", baseWorkDir, err)
		os.Exit(1)
	}

	// ── Agent identity ──────────────────────────────────────────────
	// UUID from AGENT_UUID env, or generate a new one.
	// Persisted to {workDir}/agent/agent.uuid for stable identity across
	// restarts. Use AGENT_NEW_UUID=1 to force a fresh UUID.
	agentWorkDir := filepath.Join(baseWorkDir, "agent")
	uuidFile := filepath.Join(agentWorkDir, "agent.uuid")
	if err := os.MkdirAll(agentWorkDir, 0755); err != nil {
		agentlog.Logger.Error().Str("dir", agentWorkDir).Err(err).Msg("cannot create agent work directory")
		fmt.Fprintf(os.Stderr, "gocd-agent: cannot create %s: %v\n", agentWorkDir, err)
		os.Exit(1)
	}

	agentUUID := resolveAgentUUID(uuidFile)

	// ── Reap orphaned Docker containers from prior agent runs ───────
	// Testcontainers Ryuk pattern: label containers with agent UUID,
	// clean up any survivors from crashes or unclean shutdowns.
	reaper := docker.NewReaper(agentUUID)
	if err := reaper.ReapOrphans(context.Background()); err != nil {
		// Non-fatal — agent continues without reaping.
		agentlog.Logger.Warn().Err(err).Msg("failed to reap orphan containers")
	}

	// ── PID file: {uuid}.pid contains OS PID ────────────────────────
	pidPath := filepath.Join(agentWorkDir, agentUUID+".pid")
	if err := writePidFile(pidPath, os.Getpid()); err != nil {
		agentlog.Logger.Error().Str("path", pidPath).Str("uuid", agentUUID).Err(err).Msg("cannot write pidfile — agent may already be running")
		fmt.Fprintf(os.Stderr, "gocd-agent: agent %s may already be running: %v\n", agentUUID, err)
		os.Exit(1)
	}
	defer os.Remove(pidPath)

	agentlog.Logger.Info().
		Str("uuid", agentUUID).
		Str("pidfile", pidPath).
		Str("work_dir", agentWorkDir).
		Msg("agent identity")

	os.Setenv("AGENT_WORK_DIR", agentWorkDir)
	os.Setenv("AGENT_UUID", agentUUID)

	consecutiveFailures := 0
	for {
		start := time.Now()
		err := runOnce(consecutiveFailures)
		elapsed := time.Since(start)

		if err == nil {
			agentlog.Logger.Info().Msg("gocd-agent stopped cleanly")
			return
		}

		// Server unavailability (planned outage, network blip) is not a crash.
		// Don't count it toward the restart limit — just retry.
		if errors.Is(err, agent.ErrServerUnavailable) {
			agentlog.Logger.Warn().Err(err).Dur("restart_delay", restartDelay).Msg("server unavailable, will retry (not counting toward crash limit)")
			time.Sleep(restartDelay)
			continue
		}

		// If agent ran successfully for a while before this failure,
		// reset the counter — transient crashes after a long healthy run
		// should not count against the restart budget.
		if elapsed >= minSuccessfulRun {
			agentlog.Logger.Info().Dur("uptime", elapsed).Int("previous_failures", consecutiveFailures).Msg("agent ran successfully before error, resetting restart counter")
			consecutiveFailures = 0
		}

		consecutiveFailures++

		if consecutiveFailures > maxRestarts {
			agentlog.Logger.Error().Int("attempts", consecutiveFailures).Int("max", maxRestarts).Msg("max restart attempts reached, giving up")
			fmt.Fprintf(os.Stderr, "gocd-agent: max restart attempts (%d) reached, exiting\n", maxRestarts)
			os.Exit(1)
		}

		agentlog.Logger.Warn().Int("attempt", consecutiveFailures).Int("max", maxRestarts).Dur("delay", restartDelay).Err(err).Msg("agent exited with error, will restart")

		time.Sleep(restartDelay)
	}
}

// runOnce executes one agent run cycle with panic recovery.
// Returns nil on clean shutdown, error on failure or panic.
func runOnce(attempt int) (err error) {
	// Crash span: emitted on panic so crashes are visible in Jaeger.
	// Uses no-op tracer if OTel is not yet initialized (safe).
	tracer := otel.Tracer("gocd-agent")
	_, crashSpan := tracer.Start(context.Background(), "agent.crash",
		trace.WithAttributes(attribute.Int("attempt", attempt)),
	)
	defer func() {
		if r := recover(); r != nil {
			stack := make([]byte, 4096)
			n := runtime.Stack(stack, false)
			crashSpan.SetAttributes(
				attribute.String("panic", fmt.Sprintf("%v", r)),
				attribute.String("stack", string(stack[:n])),
			)
			crashSpan.SetStatus(codes.Error, "agent panic")
			crashSpan.RecordError(fmt.Errorf("panic: %v", r))
			crashSpan.End()
			agentlog.Logger.Error().Int("attempt", attempt).Interface("panic", r).Msg("gocd-agent panicked, recovering")
			err = fmt.Errorf("panic recovered: %v", r)
		} else {
			crashSpan.End()
		}
	}()

	agentlog.Logger.Info().Int("attempt", attempt).Msg("starting agent run")
	return cmd.RunAgent()
}

// resolveAgentUUID determines the agent UUID:
//  1. AGENT_NEW_UUID=1 → generate fresh, overwrite file
//  2. AGENT_UUID env → use it if valid, persist to file
//  3. Existing agent.uuid file → load it if valid
//  4. None of the above (or invalid UUID found) → generate new
func resolveAgentUUID(uuidFile string) string {
	// Force fresh UUID
	if os.Getenv("AGENT_NEW_UUID") == "1" {
		id := uuid.New().String()
		if err := os.WriteFile(uuidFile, []byte(id), 0644); err != nil {
			agentlog.Logger.Warn().Err(err).Str("file", uuidFile).Msg("Failed to persist agent UUID")
		}
		agentlog.Logger.Info().Str("uuid", id).Msg("fresh agent UUID generated")
		return id
	}

	// Explicit UUID from env
	if id := os.Getenv("AGENT_UUID"); id != "" {
		if !isValidUUID(id) {
			agentlog.Logger.Warn().Str("invalid_uuid", id).Msg("AGENT_UUID env is not a valid UUID, generating fresh one")
		} else {
			if err := os.WriteFile(uuidFile, []byte(id), 0644); err != nil {
				agentlog.Logger.Warn().Err(err).Str("file", uuidFile).Msg("Failed to persist agent UUID from env")
			}
			agentlog.Logger.Info().Str("uuid", id).Msg("using supplied agent UUID")
			return id
		}
	}

	// Load existing UUID from file
	if data, err := os.ReadFile(uuidFile); err == nil {
		id := strings.TrimSpace(string(data))
		if id != "" {
			if !isValidUUID(id) {
				agentlog.Logger.Warn().Str("invalid_uuid", id).Str("file", uuidFile).Msg("persisted agent UUID is invalid, generating fresh one")
			} else {
				agentlog.Logger.Info().Str("uuid", id).Msg("loaded existing agent UUID")
				return id
			}
		}
	}

	// Generate new
	id := uuid.New().String()
	if err := os.WriteFile(uuidFile, []byte(id), 0644); err != nil {
		agentlog.Logger.Warn().Err(err).Str("file", uuidFile).Msg("Failed to persist agent UUID")
	}
	agentlog.Logger.Info().Str("uuid", id).Msg("generated new agent UUID")
	return id
}

// isValidUUID returns true if s looks like a valid agent identifier.
// We accept any non-empty string — our server stores UUIDs as strings
// and supports human-readable IDs like "ci-agent-00000000-...".
func isValidUUID(s string) bool {
	return len(strings.TrimSpace(s)) > 0
}

// writePidFile atomically writes the PID file (named {uuid}.pid, contains OS PID).
// Returns error if a live agent already holds the pidfile.
func writePidFile(path string, pid int) error {
	// Check for existing pidfile
	if existing, err := os.ReadFile(path); err == nil {
		var existingPID int
		if _, scanErr := fmt.Sscanf(strings.TrimSpace(string(existing)), "%d", &existingPID); scanErr == nil && isProcessAlive(existingPID) {
			return fmt.Errorf("agent already running with PID %d (pidfile %s)", existingPID, path)
		}
		// Stale pidfile — remove it
		agentlog.Logger.Warn().Str("path", path).Str("stale_pid", strings.TrimSpace(string(existing))).Msg("removing stale pidfile")
		os.Remove(path)
	}

	// Atomic write: temp file + rename
	tmpPath := path + ".tmp"
	content := fmt.Sprintf("%d\n", pid)
	if err := os.WriteFile(tmpPath, []byte(content), 0644); err != nil {
		return fmt.Errorf("write temp pidfile: %w", err)
	}
	if err := os.Rename(tmpPath, path); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("rename pidfile: %w", err)
	}
	return nil
}

// isProcessAlive checks if a process with the given PID exists.
func isProcessAlive(pid int) bool {
	process, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	err = process.Signal(syscall.Signal(0))
	return err == nil
}

// envInt reads an integer env var with a default fallback.
func envInt(key string, defaultVal int) int {
	if s := os.Getenv(key); s != "" {
		if v, err := strconv.Atoi(s); err == nil && v >= 0 {
			return v
		}
		agentlog.Logger.Warn().Str("key", key).Str("value", s).Int("default", defaultVal).Msg("invalid env value, using default")
	}
	return defaultVal
}

// envDuration reads a duration env var with a default fallback.
// Accepts values like "5s", "10s", "1m".
func envDuration(key string, defaultVal time.Duration) time.Duration {
	if s := os.Getenv(key); s != "" {
		if v, err := time.ParseDuration(s); err == nil && v >= 0 {
			return v
		}
		agentlog.Logger.Warn().Str("key", key).Str("value", s).Dur("default", defaultVal).Msg("invalid env value, using default")
	}
	return defaultVal
}
