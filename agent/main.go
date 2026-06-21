// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package main

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/d-led/ex_gocd/agent/cmd"
	"github.com/google/uuid"
)

const (
	maxRestarts  = 5
	restartDelay = 5 * time.Second
)

func main() {
	slog.Info("gocd-agent starting",
		"max_restarts", maxRestarts,
		"restart_delay", restartDelay,
	)

	// Resolve base work dir from env
	baseWorkDir := os.Getenv("AGENT_WORK_DIR")
	if baseWorkDir == "" {
		baseWorkDir = "work"
	}

	// Ensure base work dir exists
	if err := os.MkdirAll(baseWorkDir, 0755); err != nil {
		slog.Error("cannot create base work directory", "dir", baseWorkDir, "error", err)
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
		slog.Error("cannot create agent work directory", "dir", agentWorkDir, "error", err)
		fmt.Fprintf(os.Stderr, "gocd-agent: cannot create %s: %v\n", agentWorkDir, err)
		os.Exit(1)
	}

	agentUUID := resolveAgentUUID(uuidFile)

	// ── PID file: {uuid}.pid contains OS PID ────────────────────────
	pidPath := filepath.Join(agentWorkDir, agentUUID+".pid")
	if err := writePidFile(pidPath, os.Getpid()); err != nil {
		slog.Error("cannot write pidfile — agent may already be running",
			"path", pidPath, "uuid", agentUUID, "error", err,
		)
		fmt.Fprintf(os.Stderr, "gocd-agent: agent %s may already be running: %v\n", agentUUID, err)
		os.Exit(1)
	}
	defer os.Remove(pidPath)

	slog.Info("agent identity", "uuid", agentUUID,
		"pidfile", pidPath, "work_dir", agentWorkDir)

	os.Setenv("AGENT_WORK_DIR", agentWorkDir)
	os.Setenv("AGENT_UUID", agentUUID)

	for attempt := 0; attempt <= maxRestarts; attempt++ {
		err := runOnce(attempt)
		if err == nil {
			slog.Info("gocd-agent stopped cleanly")
			return
		}

		if attempt >= maxRestarts {
			slog.Error("max restart attempts reached, giving up",
				"attempts", attempt,
				"max", maxRestarts,
			)
			fmt.Fprintf(os.Stderr, "gocd-agent: max restart attempts (%d) reached, exiting\n", maxRestarts)
			os.Exit(1)
		}

		slog.Warn("agent exited with error, will restart",
			"attempt", attempt,
			"next_attempt", attempt+1,
			"max", maxRestarts,
			"delay", restartDelay,
			"error", err,
		)

		time.Sleep(restartDelay)
	}
}

// runOnce executes one agent run cycle with panic recovery.
// Returns nil on clean shutdown, error on failure or panic.
func runOnce(attempt int) (err error) {
	defer func() {
		if r := recover(); r != nil {
			slog.Error("gocd-agent panicked, recovering",
				"attempt", attempt,
				"panic", fmt.Sprintf("%v", r),
			)
			err = fmt.Errorf("panic recovered: %v", r)
		}
	}()

	slog.Info("starting agent run", "attempt", attempt)
	return cmd.RunAgent()
}

// resolveAgentUUID determines the agent UUID:
//   1. AGENT_NEW_UUID=1 → generate fresh, overwrite file
//   2. AGENT_UUID env → use it, persist to file
//   3. Existing agent.uuid file → load it
//   4. None of the above → generate new
func resolveAgentUUID(uuidFile string) string {
	// Force fresh UUID
	if os.Getenv("AGENT_NEW_UUID") == "1" {
		id := uuid.New().String()
		os.WriteFile(uuidFile, []byte(id), 0644)
		slog.Info("fresh agent UUID generated", "uuid", id)
		return id
	}

	// Explicit UUID from env
	if id := os.Getenv("AGENT_UUID"); id != "" {
		os.WriteFile(uuidFile, []byte(id), 0644)
		slog.Info("using supplied agent UUID", "uuid", id)
		return id
	}

	// Load existing UUID from file
	if data, err := os.ReadFile(uuidFile); err == nil {
		id := strings.TrimSpace(string(data))
		if id != "" {
			slog.Info("loaded existing agent UUID", "uuid", id)
			return id
		}
	}

	// Generate new
	id := uuid.New().String()
	os.WriteFile(uuidFile, []byte(id), 0644)
	slog.Info("generated new agent UUID", "uuid", id)
	return id
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
		slog.Warn("removing stale pidfile", "path", path, "stale_pid", string(existing))
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
