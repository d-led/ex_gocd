// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package remoting

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"

	"github.com/d-led/ex_gocd/agent/internal/config"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestParseWork_NoWork ensures GetWork returns nil for NoWork and other non-build types.
func TestParseWork_NoWork(t *testing.T) {
	body := []byte(`{"type":"NoWork"}`)
	var w Work
	err := json.Unmarshal(body, &w)
	require.NoError(t, err)
	assert.Equal(t, "NoWork", w.Type)
	assert.Nil(t, w.Assignment)

	// ToBuild on NoWork-like work (assignment nil) returns nil
	build := w.ToBuild("https://server")
	assert.Nil(t, build)
}

// TestParseWork_BuildWork parses BuildWork JSON and ToBuild yields correct protocol.Build.
func TestParseWork_BuildWork(t *testing.T) {
	// Minimal BuildWork shape matching Java BuildAssignment + CommandBuilderWithArgList
	body := []byte(`{
		"type": "BuildWork",
		"assignment": {
			"buildWorkingDirectory": {"path": "/tmp/build"},
			"jobIdentifier": {
				"pipelineName": "p",
				"pipelineCounter": 1,
				"pipelineLabel": "1",
				"stageName": "s",
				"stageCounter": "1",
				"buildName": "job1",
				"buildId": 42
			},
			"builders": [
				{
					"type": "CommandBuilderWithArgList",
					"command": "echo",
					"args": ["hello"],
					"workingDir": {"path": "sub"}
				}
			]
		}
	}`)
	var w Work
	err := json.Unmarshal(body, &w)
	require.NoError(t, err)
	require.NotNil(t, w.Assignment)
	assert.Equal(t, "p", w.Assignment.JobIdentifier.PipelineName)
	assert.Equal(t, "job1", w.Assignment.JobIdentifier.BuildName)
	assert.Equal(t, int64(42), w.Assignment.JobIdentifier.BuildId)

	serverBase := "https://gocd.example.com"
	build := w.ToBuild(serverBase)
	require.NotNil(t, build)
	assert.Equal(t, "p/1/s/1/job1", build.BuildId)
	assert.Contains(t, build.ConsoleUrl, "remoting/files/p/1/s/1/job1/cruise-output/console.log")
	require.NotNil(t, build.BuildCommand)
	assert.Equal(t, "compose", build.BuildCommand.Name)
	require.Len(t, build.BuildCommand.SubCommands, 1)
	assert.Equal(t, "exec", build.BuildCommand.SubCommands[0].Name)
	assert.Equal(t, "echo", build.BuildCommand.SubCommands[0].Command)
	assert.Equal(t, []string{"hello"}, build.BuildCommand.SubCommands[0].Args)
	assert.Equal(t, "sub", build.BuildCommand.SubCommands[0].WorkingDir)
}

// TestParseWork_CommandBuilderStringArgs parses CommandBuilder with args as single string.
func TestParseWork_CommandBuilderStringArgs(t *testing.T) {
	body := []byte(`{
		"type": "BuildWork",
		"assignment": {
			"buildWorkingDirectory": {"path": "/wd"},
			"jobIdentifier": {
				"pipelineName": "pipe",
				"pipelineCounter": 2,
				"pipelineLabel": "2",
				"stageName": "stage",
				"stageCounter": "1",
				"buildName": "defaultJob",
				"buildId": 100
			},
			"builders": [
				{"type": "CommandBuilder", "command": "git", "args": "clone https://example.com repo"}
			]
		}
	}`)
	var w Work
	err := json.Unmarshal(body, &w)
	require.NoError(t, err)
	build := w.ToBuild("https://server")
	require.NotNil(t, build)
	require.NotNil(t, build.BuildCommand)
	require.Len(t, build.BuildCommand.SubCommands, 1)
	// CommandBuilder with string args: we put single arg as one element
	assert.Equal(t, "git", build.BuildCommand.SubCommands[0].Command)
	assert.Equal(t, []string{"clone https://example.com repo"}, build.BuildCommand.SubCommands[0].Args)
}

// TestBuildConsoleURL covers console URL construction when server URL has or lacks trailing slash.
func TestBuildConsoleURL(t *testing.T) {
	jobID := &JobIdentifier{
		PipelineName: "p", PipelineLabel: "1", StageName: "s", StageCounter: "1", BuildName: "j",
	}
	assert.Contains(t, buildConsoleURL("https://go.example.com", jobID), "remoting/files/p/1/s/1/j/cruise-output/console.log")
	assert.Contains(t, buildConsoleURL("https://go.example.com/", jobID), "remoting/files/p/1/s/1/j/cruise-output/console.log")
	assert.Empty(t, buildConsoleURL("", jobID))
	assert.Empty(t, buildConsoleURL("https://x", nil))
}

// TestPing_viaServer tests Ping response parsing (NONE, CANCEL, quoted) via httptest.
func TestPing_viaServer(t *testing.T) {
	dir := t.TempDir()
	configDir := filepath.Join(dir, "config")
	require.NoError(t, os.MkdirAll(configDir, 0755))
	tokenPath := filepath.Join(configDir, "token")
	require.NoError(t, os.WriteFile(tokenPath, []byte("test-token"), 0644))

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/remoting/api/agent/ping" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		// Respond with instruction as JSON string (Go/CD style)
		_, _ = w.Write([]byte(`"NONE"`))
	}))
	defer server.Close()

	serverURL, err := url.Parse(server.URL)
	require.NoError(t, err)
	cfg := &config.Config{
		ServerURL: serverURL,
		WorkDir:   dir,
		ConfigDir: configDir,
		UUID:      "test-uuid",
	}
	client, err := NewClient(cfg, server.Client())
	require.NoError(t, err)

	info := &protocol.AgentRuntimeInfo{}
	instruction, err := client.Ping(info)
	require.NoError(t, err)
	assert.Equal(t, "NONE", instruction)
}

// TestPing_CANCEL_viaServer ensures CANCEL instruction is returned trimmed.
func TestPing_CANCEL_viaServer(t *testing.T) {
	dir := t.TempDir()
	configDir := filepath.Join(dir, "config")
	require.NoError(t, os.MkdirAll(configDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(configDir, "token"), []byte("t"), 0644))

	var response []byte
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(response)
	}))
	defer server.Close()

	serverURL, _ := url.Parse(server.URL)
	cfg := &config.Config{ServerURL: serverURL, WorkDir: dir, ConfigDir: configDir, UUID: "u"}
	client, err := NewClient(cfg, server.Client())
	require.NoError(t, err)

	response = []byte(`"CANCEL"`)
	instruction, err := client.Ping(nil)
	require.NoError(t, err)
	assert.Equal(t, "CANCEL", instruction)
}
