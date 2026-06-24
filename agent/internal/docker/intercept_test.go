// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package docker

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestInterceptDockerArgs_NonDockerCommand(t *testing.T) {
	args := InterceptDockerArgs("/usr/bin/git", []string{"clone", "https://example.com/repo"}, "agent-1", "")
	assert.Equal(t, []string{"clone", "https://example.com/repo"}, args)
}

func TestInterceptDockerArgs_NotRunOrCreate(t *testing.T) {
	args := InterceptDockerArgs("/usr/bin/docker", []string{"ps"}, "agent-1", "")
	assert.Equal(t, []string{"ps"}, args)
}

func TestInterceptDockerArgs_EmptyArgs(t *testing.T) {
	args := InterceptDockerArgs("/usr/bin/docker", []string{}, "agent-1", "")
	assert.Equal(t, []string{}, args)
}

func TestInterceptDockerArgs_DockerRunSimple(t *testing.T) {
	args := InterceptDockerArgs("/usr/bin/docker", []string{"run", "alpine"}, "agent-uuid-123", "")

	assert.Equal(t, []string{
		"run",
		"--label", "com.gocd.agent-uuid=agent-uuid-123",
		"alpine",
	}, args)
}

func TestInterceptDockerArgs_DockerRunWithFlags(t *testing.T) {
	args := InterceptDockerArgs("/usr/bin/docker",
		[]string{"run", "--rm", "-e", "FOO=bar", "-v", "/host:/container", "ubuntu:22.04", "echo", "hello"},
		"agent-uuid-123", "")

	assert.Equal(t, []string{
		"run",
		"--rm", "-e", "FOO=bar", "-v", "/host:/container",
		"--label", "com.gocd.agent-uuid=agent-uuid-123",
		"ubuntu:22.04", "echo", "hello",
	}, args)
}

func TestInterceptDockerArgs_DockerCreate(t *testing.T) {
	args := InterceptDockerArgs("/usr/bin/docker",
		[]string{"create", "--name", "mycontainer", "alpine"},
		"agent-abc", "")

	assert.Equal(t, []string{
		"create",
		"--name", "mycontainer",
		"--label", "com.gocd.agent-uuid=agent-abc",
		"alpine",
	}, args)
}

func TestInterceptDockerArgs_WithBuildID(t *testing.T) {
	args := InterceptDockerArgs("/usr/bin/docker",
		[]string{"run", "alpine"},
		"agent-uuid-123", "build-456")

	assert.Equal(t, []string{
		"run",
		"--label", "com.gocd.agent-uuid=agent-uuid-123",
		"--label", "com.gocd.build-id=build-456",
		"alpine",
	}, args)
}

func TestInterceptDockerArgs_NoFlagsBeforeImage(t *testing.T) {
	args := InterceptDockerArgs("/usr/bin/docker",
		[]string{"run", "nginx:latest"},
		"agent-1", "")

	assert.Equal(t, []string{
		"run",
		"--label", "com.gocd.agent-uuid=agent-1",
		"nginx:latest",
	}, args)
}

func TestInterceptDockerArgs_DockerBuildNotIntercepted(t *testing.T) {
	// docker build is not intercepted — only run and create
	args := InterceptDockerArgs("/usr/bin/docker",
		[]string{"build", "-t", "myimage", "."},
		"agent-1", "")

	assert.Equal(t, []string{"build", "-t", "myimage", "."}, args)
}

func TestIsDockerRunOrCreate(t *testing.T) {
	assert.True(t, isDockerRunOrCreate("/usr/bin/docker", []string{"run", "alpine"}))
	assert.True(t, isDockerRunOrCreate("docker", []string{"create", "--name", "c", "img"}))
	assert.False(t, isDockerRunOrCreate("/usr/bin/docker", []string{"ps"}))
	assert.False(t, isDockerRunOrCreate("/usr/bin/git", []string{"run"}))
	assert.False(t, isDockerRunOrCreate("/usr/bin/docker", []string{}))
}

func TestInjectBeforeImage_AllFlags(t *testing.T) {
	result := injectBeforeImage(
		[]string{"run", "--rm", "-e", "X=1", "-p", "8080:80", "nginx", "cmd"},
		[]string{"--label", "k=v"},
	)

	assert.Equal(t, []string{
		"run",
		"--rm", "-e", "X=1", "-p", "8080:80",
		"--label", "k=v",
		"nginx", "cmd",
	}, result)
}

func TestInjectBeforeImage_NoImage(t *testing.T) {
	// Edge case: no image arg, just flags
	result := injectBeforeImage(
		[]string{"run", "--rm"},
		[]string{"--label", "k=v"},
	)

	assert.Equal(t, []string{"run", "--rm", "--label", "k=v"}, result)
}
