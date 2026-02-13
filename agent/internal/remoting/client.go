// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0
// Remoting API client for real GoCD server: polling get_work / get_cookie (POST with auth).

package remoting

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"

	"github.com/d-led/ex_gocd/agent/internal/config"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

const (
	headerAgentGUID   = "X-Agent-GUID"
	headerAuth        = "Authorization"
	acceptGoCDJSON    = "application/vnd.go.cd+json"
	contentTypeJSON   = "application/json"
)

// Client calls the GoCD remoting API (get_work, get_cookie, etc.).
type Client struct {
	baseURL    string
	uuid       string
	token      string
	httpClient *http.Client
}

// NewClient builds a remoting client. Token is read from cfg.AgentTokenFile().
func NewClient(cfg *config.Config, httpClient *http.Client) (*Client, error) {
	token, err := os.ReadFile(cfg.AgentTokenFile())
	if err != nil {
		return nil, fmt.Errorf("read agent token: %w", err)
	}
	return &Client{
		baseURL:    cfg.RemotingBaseURL(),
		uuid:       cfg.UUID,
		token:      string(bytes.TrimSpace(token)),
		httpClient: httpClient,
	}, nil
}

// post sends a POST to the remoting API with auth headers and JSON body.
func (c *Client) post(action string, reqBody interface{}) ([]byte, error) {
	url := c.baseURL + action
	body, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set(headerAgentGUID, c.uuid)
	req.Header.Set(headerAuth, c.token)
	req.Header.Set("Accept", acceptGoCDJSON)
	req.Header.Set("Content-Type", contentTypeJSON)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	out, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("remoting %s: status %d, body: %s", action, resp.StatusCode, string(out))
	}
	return out, nil
}

// GetWorkRequest is the request body for get_work (matches GoCD GetWorkRequest).
type GetWorkRequest struct {
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
}

// GetCookieRequest is the request body for get_cookie.
type GetCookieRequest struct {
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
}

// PingRequest is the request body for ping (same shape as other agent requests).
type PingRequest struct {
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
}

// Ping calls POST ping and returns the server instruction (NONE, CANCEL, KILL_RUNNING_TASKS).
func (c *Client) Ping(runtimeInfo *protocol.AgentRuntimeInfo) (string, error) {
	body, err := c.post("/ping", &PingRequest{AgentRuntimeInfo: runtimeInfo})
	if err != nil {
		return "", err
	}
	var s string
	if err := json.Unmarshal(body, &s); err != nil {
		return "", fmt.Errorf("parse ping response: %w", err)
	}
	return strings.Trim(strings.TrimSpace(s), `"`), nil
}

// GetCookie calls POST get_cookie and returns the cookie string.
func (c *Client) GetCookie(runtimeInfo *protocol.AgentRuntimeInfo) (string, error) {
	body, err := c.post("/get_cookie", &GetCookieRequest{AgentRuntimeInfo: runtimeInfo})
	if err != nil {
		return "", err
	}
	var s string
	if err := json.Unmarshal(body, &s); err != nil {
		return "", fmt.Errorf("parse get_cookie response: %w", err)
	}
	return s, nil
}

// Work is the GoCD Work response (Serialization uses "type" discriminator: NoWork, BuildWork, etc.).
type Work struct {
	Type       string           `json:"type"` // "BuildWork", "NoWork", "DeniedAgentWork", "UnregisteredAgentWork"
	Assignment *BuildAssignment `json:"assignment,omitempty"`
}

// BuildAssignment matches Java BuildAssignment: buildWorkingDirectory (File), builders, jobIdentifier.
type BuildAssignment struct {
	BuildWorkingDirectory *FilePath       `json:"buildWorkingDirectory,omitempty"`
	Builders              []interface{}  `json:"builders,omitempty"`
	JobIdentifier         *JobIdentifier `json:"jobIdentifier,omitempty"`
}

// FilePath matches Java File serialization: {"path": "..."}.
type FilePath struct {
	Path string `json:"path"`
}

// JobIdentifier matches Java JobIdentifier (@Expose): pipelineName, pipelineCounter, pipelineLabel, stageName, stageCounter, buildName, buildId.
type JobIdentifier struct {
	PipelineName    string `json:"pipelineName"`
	PipelineCounter int    `json:"pipelineCounter"`
	PipelineLabel   string `json:"pipelineLabel"`
	StageName       string `json:"stageName"`
	StageCounter    string `json:"stageCounter"` // Java uses String
	BuildName       string `json:"buildName"`    // Java calls the job "buildName"
	BuildId         int64  `json:"buildId"`
}

// GetWork calls POST get_work and returns Work (nil if no work or NoWork).
func (c *Client) GetWork(runtimeInfo *protocol.AgentRuntimeInfo) (*Work, error) {
	body, err := c.post("/get_work", &GetWorkRequest{AgentRuntimeInfo: runtimeInfo})
	if err != nil {
		return nil, err
	}
	if len(body) == 0 {
		return nil, nil
	}
	var w Work
	if err := json.Unmarshal(body, &w); err != nil {
		return nil, fmt.Errorf("parse get_work response: %w", err)
	}
	// Only BuildWork has assignment (Java Serialization: type discriminator)
	if w.Type != "BuildWork" || w.Assignment == nil {
		return nil, nil
	}
	return &w, nil
}

// ToBuild converts remoting Work (BuildWork) to protocol.Build for handleBuild.
// Returns nil if this work is not a runnable build (e.g. NoWork already filtered).
func (w *Work) ToBuild(serverBaseURL string) *protocol.Build {
	if w == nil || w.Assignment == nil {
		return nil
	}
	a := w.Assignment
	jobID := ""
	if a.JobIdentifier != nil {
		jobID = fmt.Sprintf("%s/%d/%s/%s/%s",
			a.JobIdentifier.PipelineName, a.JobIdentifier.PipelineCounter,
			a.JobIdentifier.StageName, a.JobIdentifier.StageCounter,
			a.JobIdentifier.BuildName)
	}
	// Console URL: GoCD uses /remoting/files/<pipeline>/<label>/<stage>/<counter>/<job>/cruise-output/console.log
	consoleURL := buildConsoleURL(serverBaseURL, a.JobIdentifier)
	buildCmd := remotingAssignmentToBuildCommand(a)
	return &protocol.Build{
		BuildId:       jobID,
		BuildLocator:  jobID,
		ConsoleUrl:    consoleURL,
		BuildCommand:  buildCmd,
	}
}

// buildConsoleURL returns the GoCD remoting console log URL for a job (server base + standard path).
func buildConsoleURL(serverBaseURL string, jobID *JobIdentifier) string {
	if serverBaseURL == "" || jobID == nil {
		return ""
	}
	// Standard path: <serverPath>/remoting/files/<pipeline>/<label>/<stage>/<counter>/<job>/cruise-output/console.log
	base := strings.TrimSuffix(serverBaseURL, "/")
	path := fmt.Sprintf("remoting/files/%s/%s/%s/%s/%s/cruise-output/console.log",
		jobID.PipelineName, jobID.PipelineLabel, jobID.StageName, jobID.StageCounter, jobID.BuildName)
	if strings.HasSuffix(base, "/") {
		return base + path
	}
	return base + "/" + path
}

// remotingAssignmentToBuildCommand converts GoCD BuildAssignment to our BuildCommand tree.
// Java BuildAssignment has buildWorkingDirectory (File), builders (List<Builder>). Builder subtypes: CommandBuilder, CommandBuilderWithArgList, etc.
func remotingAssignmentToBuildCommand(a *BuildAssignment) *protocol.BuildCommand {
	if a == nil || len(a.Builders) == 0 {
		return nil
	}
	workingDir := ""
	if a.BuildWorkingDirectory != nil {
		workingDir = a.BuildWorkingDirectory.Path
	}
	var subCommands []*protocol.BuildCommand
	for _, b := range a.Builders {
		cmd := mapBuilderToCommand(b)
		if cmd != nil {
			subCommands = append(subCommands, cmd)
		}
	}
	if len(subCommands) == 0 {
		return nil
	}
	return &protocol.BuildCommand{
		Name:        "compose",
		SubCommands: subCommands,
		WorkingDir:  workingDir,
	}
}

// mapBuilderToCommand maps Java Builder JSON to our BuildCommand.
// Subtypes: CommandBuilder (args string), CommandBuilderWithArgList (args []string). Both have type, command, workingDir (File with path).
func mapBuilderToCommand(b interface{}) *protocol.BuildCommand {
	m, ok := b.(map[string]interface{})
	if !ok {
		return nil
	}
	// Skip non-command builders (NullBuilder, FetchArtifactBuilder, etc.)
	builderType, _ := m["type"].(string)
	cmd, _ := m["command"].(string)
	if cmd == "" {
		return nil
	}
	var args []string
	switch a := m["args"].(type) {
	case []interface{}:
		for _, v := range a {
			if s, ok := v.(string); ok {
				args = append(args, s)
			}
		}
	case string:
		if a != "" {
			args = append(args, a)
		}
	}
	wd := ""
	if w, ok := m["workingDir"].(map[string]interface{}); ok {
		wd, _ = w["path"].(string)
	}
	// CommandBuilder and CommandBuilderWithArgList both become exec
	if builderType == "CommandBuilder" || builderType == "CommandBuilderWithArgList" || cmd != "" {
		return &protocol.BuildCommand{
			Name:       "exec",
			Command:   cmd,
			Args:      args,
			WorkingDir: wd,
		}
	}
	return nil
}

// ReportCurrentStatusRequest is the body for report_current_status.
type ReportCurrentStatusRequest struct {
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
	JobIdentifier    *JobIdentifier             `json:"jobIdentifier"`
	JobState         string                     `json:"jobState"`
}

// ReportCompleteStatusRequest is the body for report_completing and report_completed.
type ReportCompleteStatusRequest struct {
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
	JobIdentifier    *JobIdentifier             `json:"jobIdentifier"`
	JobResult        string                     `json:"jobResult"`
}

// ReportCurrentStatus sends Building/Completing state to the server.
func (c *Client) ReportCurrentStatus(runtimeInfo *protocol.AgentRuntimeInfo, jobID *JobIdentifier, jobState string) error {
	_, err := c.post("/report_current_status", &ReportCurrentStatusRequest{
		AgentRuntimeInfo: runtimeInfo,
		JobIdentifier:    jobID,
		JobState:         jobState,
	})
	return err
}

// ReportCompleting sends the job is completing with a result (Passed/Failed/Cancelled).
func (c *Client) ReportCompleting(runtimeInfo *protocol.AgentRuntimeInfo, jobID *JobIdentifier, result string) error {
	_, err := c.post("/report_completing", &ReportCompleteStatusRequest{
		AgentRuntimeInfo: runtimeInfo,
		JobIdentifier:    jobID,
		JobResult:        result,
	})
	return err
}

// ReportCompleted sends the job has completed.
func (c *Client) ReportCompleted(runtimeInfo *protocol.AgentRuntimeInfo, jobID *JobIdentifier, result string) error {
	_, err := c.post("/report_completed", &ReportCompleteStatusRequest{
		AgentRuntimeInfo: runtimeInfo,
		JobIdentifier:    jobID,
		JobResult:        result,
	})
	return err
}
