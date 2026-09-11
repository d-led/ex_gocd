// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package remoting

import (
	"context"
	"encoding/json"
	"io"
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

func testInfo() *protocol.AgentRuntimeInfo {
	return &protocol.AgentRuntimeInfo{
		Type: "AgentRuntimeInfo",
		Identifier: &protocol.AgentIdentifier{
			HostName:  "test-host",
			IpAddress: "127.0.0.1",
			Uuid:      "test-uuid",
		},
		RuntimeStatus:                "Idle",
		Location:                     "/work",
		UsableSpace:                  1234,
		OperatingSystemName:          "linux",
		AgentBootstrapperVersion:     AgentBootstrapperVersion,
		AgentVersion:                 AgentVersion,
		SupportsBuildCommandProtocol: true,
	}
}

func testClient(t *testing.T, serverURL *url.URL) *Client {
	t.Helper()
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "token"), []byte("secret-token\n"), 0600))

	cfg := &config.Config{
		ServerURL: serverURL,
		UUID:      "test-uuid",
		ConfigDir: dir,
	}
	client, err := NewClient(cfg, nil)
	require.NoError(t, err)
	return client
}

func TestPingSendsRemotingHeaders(t *testing.T) {
	var method, path, accept, contentType, guid, auth string
	var body PingRequest

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		method = r.Method
		path = r.URL.Path
		accept = r.Header.Get("Accept")
		contentType = r.Header.Get("Content-Type")
		guid = r.Header.Get("X-Agent-GUID")
		auth = r.Header.Get("Authorization")
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, &body)
		w.Header().Set("Content-Type", responseContentType)
		_, _ = w.Write([]byte(`"NONE"`))
	}))
	defer ts.Close()

	u, err := url.Parse(ts.URL)
	require.NoError(t, err)

	err = testClient(t, u).Ping(context.Background(), testInfo())
	assert.NoError(t, err)
	assert.Equal(t, http.MethodPost, method)
	assert.Equal(t, "/remoting/api/agent/ping", path)
	assert.Equal(t, responseContentType, accept)
	assert.Equal(t, requestContentType, contentType)
	assert.Equal(t, "test-uuid", guid)
	assert.Equal(t, "secret-token", auth)
	assert.Equal(t, TypePingRequest, body.Type)
	assert.Equal(t, "test-uuid", body.AgentRuntimeInfo.Identifier.Uuid)
}

func TestGetWorkNoWork(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", responseContentType)
		_, _ = w.Write([]byte(`{"type":"NoWork"}`))
	}))
	defer ts.Close()

	u, _ := url.Parse(ts.URL)
	work, err := testClient(t, u).GetWork(context.Background(), testInfo())
	assert.NoError(t, err)
	assert.Nil(t, work)
}

func TestGetWorkDecodesBuildWork(t *testing.T) {
	payload, err := os.ReadFile(filepath.Join("..", "..", "..", "test", "fixtures", "remoting", "build_work_response.json"))
	require.NoError(t, err)

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", responseContentType)
		_, _ = w.Write(payload)
	}))
	defer ts.Close()

	u, _ := url.Parse(ts.URL)
	work, err := testClient(t, u).GetWork(context.Background(), testInfo())
	require.NoError(t, err)
	require.NotNil(t, work)
	assert.Equal(t, int64(35), work.Assignment.JobIdentifier.BuildID)
}

func TestGetCookieRawText(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", responseContentType)
		_, _ = w.Write([]byte("cookie-value-123"))
	}))
	defer ts.Close()

	u, _ := url.Parse(ts.URL)
	cookie, err := testClient(t, u).GetCookie(context.Background(), testInfo())
	assert.NoError(t, err)
	assert.Equal(t, "cookie-value-123", cookie)
}

func TestIsIgnoredParsesBareBool(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("false"))
	}))
	defer ts.Close()

	u, _ := url.Parse(ts.URL)
	ignored, err := testClient(t, u).IsIgnored(context.Background(), testInfo(), JobIdentifier{})
	assert.NoError(t, err)
	assert.False(t, ignored)
}

func TestReportsPostToTheirActions(t *testing.T) {
	var actions []string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		actions = append(actions, r.URL.Path)
		w.WriteHeader(http.StatusOK)
	}))
	defer ts.Close()

	u, _ := url.Parse(ts.URL)
	client := testClient(t, u)
	job := JobIdentifier{BuildID: 35}

	assert.NoError(t, client.ReportCurrentStatus(context.Background(), testInfo(), job, "Building"))
	assert.NoError(t, client.ReportCompleting(context.Background(), testInfo(), job, "Passed"))
	assert.NoError(t, client.ReportCompleted(context.Background(), testInfo(), job, "Passed"))

	assert.Equal(t, []string{
		"/remoting/api/agent/report_current_status",
		"/remoting/api/agent/report_completing",
		"/remoting/api/agent/report_completed",
	}, actions)
}

func TestUploadConsoleLogUsesPutWithArtifactSize(t *testing.T) {
	var method, path, size string
	var body string

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		method = r.Method
		path = r.URL.RequestURI()
		size = r.Header.Get("X-Go-Artifact-Size")
		raw, _ := io.ReadAll(r.Body)
		body = string(raw)
		w.WriteHeader(http.StatusOK)
	}))
	defer ts.Close()

	u, _ := url.Parse(ts.URL)
	job := JobIdentifier{
		PipelineName:    "capture-protocol",
		PipelineCounter: 3,
		StageName:       "probe",
		StageCounter:    "1",
		BuildName:       "probe-job",
		BuildID:         35,
	}

	content := "hello from the build\n"
	err := testClient(t, u).UploadConsoleLog(context.Background(), job, content)
	assert.NoError(t, err)
	assert.Equal(t, http.MethodPut, method)
	assert.Equal(t, "/remoting/files/capture-protocol/3/probe/1/probe-job/cruise-output/console.log?attempt=1&buildId=35", path)
	assert.Equal(t, "21", size)
	assert.Equal(t, content, body)
}
