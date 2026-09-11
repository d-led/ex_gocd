// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package remoting

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/d-led/ex_gocd/agent/internal/config"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

const (
	// responseContentType is what the server answers every remoting action with.
	responseContentType = "application/vnd.go.cd.v1+json;charset=utf-8"
	// requestContentType is what the Java agent sends.
	requestContentType = "application/json; charset=UTF-8"

	// AgentVersion is the agent's own reported version string. The Java agent
	// sends its GoCD build number here; a distinct value is fine because the
	// server only logs it.
	AgentVersion = "0.1.0"
	// AgentBootstrapperVersion mirrors the Java agent, which sends "UNKNOWN".
	AgentBootstrapperVersion = "UNKNOWN"
)

// ErrUnexpectedStatus wraps HTTP responses outside 2xx from a remoting call.
var ErrUnexpectedStatus = errors.New("unexpected remoting response")

// ErrNoWork is returned by GetWork when the server has no assignment. Callers
// typically treat it as "keep polling"; it is exposed so they can distinguish
// it from a real transport error.
var ErrNoWork = errors.New("no work available")

// Client talks the GoCD agent remoting protocol over HTTP.
type Client struct {
	cfg   *config.Config
	http  *http.Client
	token string
}

// NewClient builds a Client using the token already written by registration.
func NewClient(cfg *config.Config, tlsConfig *tls.Config) (*Client, error) {
	tokenBytes, err := os.ReadFile(cfg.AgentTokenFile())
	if err != nil {
		return nil, fmt.Errorf("read agent token: %w", err)
	}
	return &Client{
		cfg: cfg,
		http: &http.Client{
			Transport: &http.Transport{
				TLSClientConfig: tlsConfig,
			},
			Timeout: 60 * time.Second,
		},
		token: strings.TrimSpace(string(tokenBytes)),
	}, nil
}

// Ping sends a heartbeat and returns the server's instruction (normally "NONE").
func (c *Client) Ping(ctx context.Context, info *protocol.AgentRuntimeInfo) error {
	body := PingRequest{Type: TypePingRequest, AgentRuntimeInfo: info}
	var instruction string
	if err := c.doJSON(ctx, "ping", body, &instruction); err != nil {
		return err
	}
	if instruction != "NONE" {
		return fmt.Errorf("unexpected instruction from ping: %q", instruction)
	}
	return nil
}

// GetWork asks the server for an assignment. It returns (nil, nil) when the
// server answers NoWork, and the decoded BuildWork otherwise.
func (c *Client) GetWork(ctx context.Context, info *protocol.AgentRuntimeInfo) (*Work, error) {
	body := GetWorkRequest{Type: TypeGetWorkRequest, AgentRuntimeInfo: info}
	var work Work
	if err := c.doJSON(ctx, "get_work", body, &work); err != nil {
		return nil, err
	}
	switch work.Type {
	case TypeNoWork:
		return nil, nil
	case TypeBuildWork:
		return &work, nil
	default:
		return nil, fmt.Errorf("unknown work type %q", work.Type)
	}
}

// GetCookie fetches the session cookie as plain text.
func (c *Client) GetCookie(ctx context.Context, info *protocol.AgentRuntimeInfo) (string, error) {
	body := GetCookieRequest{Type: TypeGetCookieRequest, AgentRuntimeInfo: info}
	return c.doRaw(ctx, "get_cookie", body)
}

// IsIgnored reports whether the server has discarded the given assignment.
func (c *Client) IsIgnored(ctx context.Context, info *protocol.AgentRuntimeInfo, job JobIdentifier) (bool, error) {
	body := IsIgnoredRequest{Type: TypeIsIgnoredRequest, AgentRuntimeInfo: info, JobIdentifier: job}
	raw, err := c.doRaw(ctx, "is_ignored", body)
	if err != nil {
		return false, err
	}
	ignored, err := strconv.ParseBool(strings.TrimSpace(raw))
	if err != nil {
		return false, fmt.Errorf("is_ignored returned %q: %w", raw, err)
	}
	return ignored, nil
}

// ReportCurrentStatus reports an in-progress job state change (e.g. "Building").
func (c *Client) ReportCurrentStatus(ctx context.Context, info *protocol.AgentRuntimeInfo, job JobIdentifier, jobState string) error {
	body := ReportCurrentStatusRequest{
		Type:             TypeReportCurrentStatus,
		AgentRuntimeInfo: info,
		JobIdentifier:    job,
		JobState:         jobState,
	}
	return c.doJSON(ctx, "report_current_status", body, nil)
}

// ReportCompleting reports the job's result while it is finishing.
func (c *Client) ReportCompleting(ctx context.Context, info *protocol.AgentRuntimeInfo, job JobIdentifier, result string) error {
	body := ReportCompleteStatusRequest{
		Type:             TypeReportCompleteStatus,
		AgentRuntimeInfo: info,
		JobIdentifier:    job,
		JobResult:        result,
	}
	return c.doJSON(ctx, "report_completing", body, nil)
}

// ReportCompleted reports the job's final result.
func (c *Client) ReportCompleted(ctx context.Context, info *protocol.AgentRuntimeInfo, job JobIdentifier, result string) error {
	body := ReportCompleteStatusRequest{
		Type:             TypeReportCompleteStatus,
		AgentRuntimeInfo: info,
		JobIdentifier:    job,
		JobResult:        result,
	}
	return c.doJSON(ctx, "report_completed", body, nil)
}

// UploadConsoleLog appends console output to the job's console log. The server
// expects a PUT with the body length in X-Go-Artifact-Size.
func (c *Client) UploadConsoleLog(ctx context.Context, job JobIdentifier, content string) error {
	url := c.consoleLogURL(job)
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, url, strings.NewReader(content))
	if err != nil {
		return err
	}
	c.setCommonHeaders(req)
	req.Header.Set("Content-Type", "text/plain; charset=utf-8")
	req.Header.Set("X-Go-Artifact-Size", strconv.Itoa(len(content)))

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("upload console log: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("upload console log: %w: status %d: %s", ErrUnexpectedStatus, resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}

// doJSON marshals requestBody, POSTs it to an action, and decodes the response
// into out (when non-nil). A 2xx with an empty body leaves out untouched.
func (c *Client) doJSON(ctx context.Context, action string, requestBody any, out any) error {
	payload, err := json.Marshal(requestBody)
	if err != nil {
		return fmt.Errorf("%s: marshal request: %w", action, err)
	}
	req, err := c.newRequest(ctx, action, payload)
	if err != nil {
		return err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("%s: %w", action, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("%s: read response: %w", action, err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("%s: %w: status %d: %s", action, ErrUnexpectedStatus, resp.StatusCode, strings.TrimSpace(string(body)))
	}
	if out == nil || len(body) == 0 {
		return nil
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("%s: decode response: %w", action, err)
	}
	return nil
}

// doRaw POSTs requestBody and returns the raw (unparsed) response body as text.
func (c *Client) doRaw(ctx context.Context, action string, requestBody any) (string, error) {
	payload, err := json.Marshal(requestBody)
	if err != nil {
		return "", fmt.Errorf("%s: marshal request: %w", action, err)
	}
	req, err := c.newRequest(ctx, action, payload)
	if err != nil {
		return "", err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("%s: %w", action, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("%s: read response: %w", action, err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("%s: %w: status %d: %s", action, ErrUnexpectedStatus, resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return string(body), nil
}

func (c *Client) newRequest(ctx context.Context, action string, payload []byte) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.actionURL(action), strings.NewReader(string(payload)))
	if err != nil {
		return nil, fmt.Errorf("%s: build request: %w", action, err)
	}
	c.setCommonHeaders(req)
	return req, nil
}

func (c *Client) setCommonHeaders(req *http.Request) {
	req.Header.Set("Accept", responseContentType)
	req.Header.Set("Content-Type", requestContentType)
	req.Header.Set("X-Agent-GUID", c.cfg.UUID)
	req.Header.Set("Authorization", c.token)
}

// baseURL is the server URL without a trailing slash (already contains /go).
func (c *Client) baseURL() string {
	return strings.TrimSuffix(c.cfg.ServerURL.String(), "/")
}

func (c *Client) actionURL(action string) string {
	return c.baseURL() + "/remoting/api/agent/" + action
}

// filesURL is the base URL for console/artifact uploads for one job.
func (c *Client) filesURL(job JobIdentifier) string {
	return c.baseURL() + "/remoting/files/" + job.Locator()
}

func (c *Client) consoleLogURL(job JobIdentifier) string {
	return c.filesURL(job) + "/cruise-output/console.log?attempt=1&buildId=" + strconv.FormatInt(job.BuildID, 10)
}
