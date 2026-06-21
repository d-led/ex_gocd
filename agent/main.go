// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package main

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/d-led/ex_gocd/agent/cmd"
)

const (
	maxRestarts  = 5
	restartDelay = 5 * time.Second
	pidFileName  = "agent.pid"
)

func main() {
	pid := os.Getpid()
	pidStr := strconv.Itoa(pid)

	slog.Info("gocd-agent starting",
		"pid", pid,
		"max_restarts", maxRestarts,
		"restart_delay", restartDelay,
	)

	// Resolve base work dir from env (same logic as config.Load)
	baseWorkDir := os.Getenv("AGENT_WORK_DIR")
	if baseWorkDir == "" {
		baseWorkDir = "work"
	}

	// Ensure base work dir exists
	if err := os.MkdirAll(baseWorkDir, 0755); err != nil {
		slog.Error("cannot create base work directory",
			"dir", baseWorkDir,
			"error", err,
		)
		fmt.Fprintf(os.Stderr, "gocd-agent: cannot create %s: %v\n", baseWorkDir, err)
		os.Exit(1)
	}

	// Write pidfile (atomic: write temp + rename)
	pidPath := filepath.Join(baseWorkDir, pidFileName)
	if err := writePidFile(pidPath, pid); err != nil {
		slog.Error("cannot write pidfile, agent may already be running",
			"path", pidPath,
			"error", err,
		)
		fmt.Fprintf(os.Stderr, "gocd-agent: cannot write pidfile %s: %v\n", pidPath, err)
		os.Exit(1)
	}
	defer os.Remove(pidPath)

	slog.Info("pidfile written", "path", pidPath, "pid", pid)

	// Per-PID work subfolder: work/<pid>/
	pidWorkDir := filepath.Join(baseWorkDir, pidStr)
	if err := os.MkdirAll(pidWorkDir, 0755); err != nil {
		slog.Error("cannot create per-PID work directory",
			"dir", pidWorkDir,
			"error", err,
		)
		fmt.Fprintf(os.Stderr, "gocd-agent: cannot create %s: %v\n", pidWorkDir, err)
		os.Exit(1)
	}
	defer cleanupPidWorkDir(pidWorkDir)

	slog.Info("per-PID work directory", "dir", pidWorkDir)

	// Set AGENT_WORK_DIR so config.Load picks it up
	os.Setenv("AGENT_WORK_DIR", pidWorkDir)

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

// writePidFile atomically writes the PID file.
// Returns error if a live agent already holds the pidfile.
func writePidFile(path string, pid int) error {
	// Check for existing pidfile
	if existing, err := os.ReadFile(path); err == nil {
		existingPID, parseErr := strconv.Atoi(strings.TrimSpace(string(existing)))
		if parseErr == nil && isProcessAlive(existingPID) {
			return fmt.Errorf("agent already running with PID %d (pidfile %s)", existingPID, path)
		}
		// Stale pidfile — remove it
		slog.Warn("removing stale pidfile",
			"path", path,
			"stale_pid", existingPID,
		)
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
	// Send signal 0 to check existence (Unix)
	err = process.Signal(syscall.Signal(0))
	return err == nil
}

// cleanupPidWorkDir removes the per-PID work directory and logs any error.
func cleanupPidWorkDir(dir string) {
	if err := os.RemoveAll(dir); err != nil {
		slog.Warn("failed to remove per-PID work directory",
			"dir", dir,
			"error", err,
		)
	} else {
		slog.Info("removed per-PID work directory", "dir", dir)
	}
}
