// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

// Package docker provides Docker container management for the GoCD agent:
//   - Reaping orphaned containers from prior agent crashes (Testcontainers Ryuk pattern)
//   - Injecting agent-identity labels into docker run/create commands during builds
//
// Labels follow the reverse-DNS convention for namespacing, matching Docker's
// recommended practice and making containers easy to identify with docker ps --filter.
package docker

// LabelAgentUUID is the Docker label key used to tag containers spawned by this agent.
// Value is the agent's UUID, stable across restarts (persisted in agent.uuid).
const LabelAgentUUID = "com.gocd.agent-uuid"

// LabelBuildID is set on containers spawned during a specific build, enabling
// per-build cleanup and debugging.
const LabelBuildID = "com.gocd.build-id"
