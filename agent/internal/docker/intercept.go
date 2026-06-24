// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package docker

import (
	"context"
	"os/exec"
	"strings"
	"time"

	agentlog "github.com/d-led/ex_gocd/agent/internal/log"
)

// InterceptDockerArgs injects agent-identity labels into docker run/create commands.
//
// When a pipeline job runs `docker run myimage`, this function rewrites the args
// to `docker run --label com.gocd.agent-uuid=<uuid> myimage` so that containers
// are traceable back to the agent that spawned them.
//
// Also handles `docker create` (same syntax as run for our purposes).
//
// Returns the (possibly modified) args slice. If the command is not a docker
// run/create, returns args unchanged.
func InterceptDockerArgs(cmdPath string, args []string, agentUUID string, buildID string) []string {
	if !isDockerRunOrCreate(cmdPath, args) {
		return args
	}

	// Insert --label flags before the image name. The image is the first
	// non-flag argument after the subcommand.
	labelArgs := []string{
		"--label", LabelAgentUUID + "=" + agentUUID,
	}
	if buildID != "" {
		labelArgs = append(labelArgs, "--label", LabelBuildID+"="+buildID)
	}

	return injectBeforeImage(args, labelArgs)
}

// isDockerRunOrCreate returns true if the command is `docker run ...` or `docker create ...`.
func isDockerRunOrCreate(cmdPath string, args []string) bool {
	base := cmdPath
	if idx := strings.LastIndex(cmdPath, "/"); idx >= 0 {
		base = cmdPath[idx+1:]
	}
	if base != "docker" {
		return false
	}
	if len(args) == 0 {
		return false
	}
	sub := args[0]
	return sub == "run" || sub == "create"
}

// injectBeforeImage inserts labelArgs into args before the first non-flag
// positional argument (the Docker image name).
// Docker flags that take a value argument (-e, -v, -p, --name, etc.) are
// skipped with their value so the labels land before the image, not mid-flag.
func injectBeforeImage(args []string, labelArgs []string) []string {
	// args[0] is the subcommand ("run" or "create")
	result := make([]string, 0, len(args)+len(labelArgs))
	result = append(result, args[0])

	i := 1
	for i < len(args) {
		arg := args[i]
		if !strings.HasPrefix(arg, "-") {
			// First non-flag arg is the image — insert labels here
			result = append(result, labelArgs...)
			result = append(result, args[i:]...)
			return result
		}
		result = append(result, arg)
		i++

		// Flags that take a separate value argument: skip one more token.
		// Recognized by: single-dash short flag with non-empty value prefix
		// (e.g., -e, -v, -p, -m, -w, -u) or long flags that are known
		// to take values (--name, --network, --memory, etc.).
		if takesValue(arg) && i < len(args) && !strings.HasPrefix(args[i], "-") {
			result = append(result, args[i])
			i++
		}
	}

	// No image found (just flags) — append labels at the end
	result = append(result, labelArgs...)
	return result
}

// takesValue reports whether a Docker flag expects a separate value argument.
func takesValue(flag string) bool {
	// Short flags that always take a value
	if len(flag) == 2 && flag[0] == '-' && flag[1] != '-' {
		switch flag[1] {
		case 'e', 'v', 'p', 'm', 'w', 'u', 'l':
			return true
		}
		return false
	}
	// Long flags known to take values
	switch flag {
	case "--name", "--network", "--memory", "--cpus", "--cpuset-cpus",
		"--entrypoint", "--hostname", "--workdir", "--user", "--volume",
		"--env", "--publish", "--label", "--mount", "--restart",
		"--log-driver", "--log-opt":
		return true
	}
	return false
}

// runDockerCmd executes a docker CLI command and returns its stdout.
// Used by the reaper for container discovery and cleanup.
func runDockerCmd(ctx context.Context, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "docker", args...)
	out, err := cmd.Output()
	if err != nil {
		if ctx.Err() != nil {
			agentlog.Logger.Warn().Dur("timeout", 30*time.Second).Msg("docker command timed out")
		}
		return "", err
	}
	return string(out), nil
}
