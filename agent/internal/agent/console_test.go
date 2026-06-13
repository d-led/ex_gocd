// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package agent

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/d-led/ex_gocd/agent/internal/config"
	"github.com/stretchr/testify/assert"
)

func TestStreamReaderToConsole_Robust(t *testing.T) {
	var received []string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err == nil {
			received = append(received, string(body))
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer ts.Close()

	u, err := url.Parse(ts.URL)
	assert.NoError(t, err)

	cfg := &config.Config{
		ServerURL: u,
	}
	agent := &Agent{
		config: cfg,
	}

	// 1. Test normal streaming
	normalInput := "line1\nline2\n"
	agent.streamReaderToConsole(ts.URL, "prefix: ", strings.NewReader(normalInput))
	assert.Len(t, received, 2)
	assert.Contains(t, received[0], "prefix: line1\n")
	assert.Contains(t, received[1], "prefix: line2\n")

	// 2. Test very long line (should split/truncate/chunk gracefully without panic/hang)
	received = nil
	longLine := strings.Repeat("a", 70*1024) // 70KB, exceeds the 64KB buffer size
	agent.streamReaderToConsole(ts.URL, "", strings.NewReader(longLine+"\n"))

	// Should split into two chunks
	assert.True(t, len(received) >= 2)
	assert.Contains(t, received[0], " [truncated...]\n")
}
