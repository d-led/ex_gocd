// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package docker

import (
	"context"
	"strings"
	"time"

	agentlog "github.com/d-led/ex_gocd/agent/internal/log"
)

// Reaper cleans up orphaned Docker containers from a previous agent incarnation.
// Modeled after Testcontainers' Ryuk: labels containers with the agent UUID on
// creation, then reaps any matching containers on startup.
type Reaper struct {
	agentUUID string
}

// NewReaper creates a Reaper for the given agent UUID.
func NewReaper(agentUUID string) *Reaper {
	return &Reaper{agentUUID: agentUUID}
}

// ReapOrphans removes all containers (running or stopped) labeled with this
// agent's UUID. Called on agent startup before registration, so the agent
// starts with a clean slate.
//
// Uses docker CLI for maximum portability — no SDK dependency required.
// If Docker is not available, logs a warning and returns nil (no error).
func (r *Reaper) ReapOrphans(ctx context.Context) error {
	// Delegate to the CLI-based implementation. The SDK variant mirrors this
	// when the Docker SDK dependency is available.
	return r.reapViaCLI(ctx)
}

// reapViaCLI uses `docker ps` + `docker rm` to find and remove orphaned containers.
// This is the zero-dependency fallback that works anywhere docker CLI is on PATH.
func (r *Reaper) reapViaCLI(ctx context.Context) error {
	labelFilter := LabelAgentUUID + "=" + r.agentUUID

	// Find container IDs (all states: running, exited, created)
	out, err := runDockerCmd(ctx, "ps", "-a", "--filter", "label="+labelFilter, "-q")
	if err != nil {
		// Docker unavailable is not a fatal error — just log and continue.
		agentlog.Logger.Warn().Err(err).Msg("docker unavailable, skipping orphan container reaping")
		return nil
	}

	ids := strings.Fields(strings.TrimSpace(out))
	if len(ids) == 0 {
		agentlog.Logger.Info().Msg("no orphaned containers to reap")
		return nil
	}

	agentlog.Logger.Info().Int("count", len(ids)).Strs("ids", ids).Msg("reaping orphaned containers from prior agent run")

	// Force-remove all matching containers (stop + rm in one)
	rmArgs := append([]string{"rm", "-f"}, ids...)
	rmCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	_, err = runDockerCmd(rmCtx, rmArgs...)
	if err != nil {
		agentlog.Logger.Warn().Err(err).Int("count", len(ids)).Msg("failed to remove some orphaned containers")
		return nil
	}

	agentlog.Logger.Info().Int("count", len(ids)).Msg("successfully reaped orphaned containers")
	return nil
}
