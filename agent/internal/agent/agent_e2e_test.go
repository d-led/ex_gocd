// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0
// E2E test: agent executes a job and reports Passed.

package agent

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/d-led/ex_gocd/agent/internal/config"
	"github.com/d-led/ex_gocd/agent/internal/remoting"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestExecuteJob_Success runs a single build (exec echo ok) and asserts the agent reports Completed Passed.
func TestExecuteJob_Success(t *testing.T) {
	// Mock server: accept console log POST and any remoting report; we only care about capturing result.
	var completedResult string
	var mu sync.Mutex
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Console log upload (POST body is log content)
		if r.Method == http.MethodPost && r.URL.Path != "" {
			mu.Lock()
			defer mu.Unlock()
			// Capture report_completed body by checking Content-Type and parsing if needed.
			// Our send() is in-memory; we capture in the send callback below, not from server.
			_ = r
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	serverURL, err := url.Parse(server.URL)
	require.NoError(t, err)
	cfg := &config.Config{
		ServerURL:  serverURL,
		WorkingDir: t.TempDir(),
		UUID:       "e2e-agent",
		Hostname:   "localhost",
	}
	a, err := New(cfg)
	require.NoError(t, err)
	a.httpClient = server.Client()
	a.cookie = "test-cookie"

	// Build: single exec "echo" with arg "ok" (succeeds). ConsoleUrl must be valid for NewWriter.
	build := &protocol.Build{
		BuildId:      "pipeline/1/stage/1/job1",
		BuildLocator: "pipeline/1/stage/1/job1",
		ConsoleUrl:  server.URL + "/remoting/files/p/1/s/1/job1/cruise-output/console.log",
		BuildCommand: &protocol.BuildCommand{
			Name: protocol.CommandCompose,
			SubCommands: []*protocol.BuildCommand{
				{Name: protocol.CommandExec, Command: "echo", Args: []string{"ok"}},
			},
		},
	}

	var gotCompleted *protocol.Report
	send := func(msg *protocol.Message) {
		if msg.Action != protocol.ReportCompletedAction {
			return
		}
		r := msg.Report()
		if r != nil {
			mu.Lock()
			gotCompleted = r
			completedResult = r.Result
			mu.Unlock()
		}
	}

	a.handleBuildWithSend(build, send, nil)

	mu.Lock()
	result := completedResult
	report := gotCompleted
	mu.Unlock()
	require.NotNil(t, report, "agent should have sent reportCompleted")
	assert.Equal(t, "Passed", result, "job should report Passed when exec succeeds")
	assert.Equal(t, "Completed", report.JobState)
}

// buildWorkJSON is a minimal BuildWork that runs: exec echo ok.
const buildWorkJSON = `{
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
			{"type": "CommandBuilderWithArgList", "command": "echo", "args": ["ok"], "workingDir": {"path": ""}}
		]
	}
}`

// TestExecuteJob_RemotingPath runs get_cookie -> get_work (mock returns one job) -> execute -> assert Passed.
func TestExecuteJob_RemotingPath(t *testing.T) {
	dir := t.TempDir()
	configDir := filepath.Join(dir, "config")
	require.NoError(t, os.MkdirAll(configDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(configDir, "token"), []byte("test-token"), 0644))

	var completedResult string
	var mu sync.Mutex
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		switch r.URL.Path {
		case "/remoting/api/agent/get_cookie":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`"cookie123"`))
		case "/remoting/api/agent/get_work":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(buildWorkJSON))
		default:
			w.WriteHeader(http.StatusOK)
		}
	}))
	defer server.Close()

	serverURL, err := url.Parse(server.URL)
	require.NoError(t, err)
	cfg := &config.Config{
		ServerURL:  serverURL,
		WorkingDir: dir,
		ConfigDir:  configDir,
		UUID:       "e2e-remoting",
		Hostname:   "localhost",
	}
	client, err := remoting.NewClient(cfg, server.Client())
	require.NoError(t, err)

	info := &protocol.AgentRuntimeInfo{}
	cookie, err := client.GetCookie(info)
	require.NoError(t, err)
	assert.NotEmpty(t, cookie)

	work, err := client.GetWork(info)
	require.NoError(t, err)
	require.NotNil(t, work)
	build := work.ToBuild(server.URL)
	require.NotNil(t, build)
	require.NotNil(t, build.BuildCommand)

	a, err := New(cfg)
	require.NoError(t, err)
	a.httpClient = server.Client()
	a.cookie = cookie

	send := func(msg *protocol.Message) {
		if msg.Action == protocol.ReportCompletedAction {
			if r := msg.Report(); r != nil {
				mu.Lock()
				completedResult = r.Result
				mu.Unlock()
			}
		}
	}
	a.handleBuildWithSend(build, send, nil)

	mu.Lock()
	result := completedResult
	mu.Unlock()
	assert.Equal(t, "Passed", result, "remoting get_work -> execute -> report_completed should be Passed")
}
