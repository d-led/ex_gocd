// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

// Package remoting implements the GoCD agent HTTP remoting protocol
// (POST /go/remoting/api/agent/*) spoken by the official Java agent.
//
// The wire shapes in this file are not guesses: they mirror traffic captured
// verbatim from gocd/gocd-agent-alpine:v25.4.0 talking to
// gocd/gocd-server:v25.4.0. See test/fixtures/remoting/ in the server project
// for the capture procedure and the authoritative JSON.
package remoting

import (
	"encoding/json"
	"fmt"

	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

// Request `type` discriminators, as Gson serialises them.
const (
	TypePingRequest          = "PingRequest"
	TypeGetWorkRequest       = "GetWorkRequest"
	TypeGetCookieRequest     = "GetCookieRequest"
	TypeIsIgnoredRequest     = "IsIgnoredRequest"
	TypeReportCurrentStatus  = "ReportCurrentStatusRequest"
	TypeReportCompleteStatus = "ReportCompleteStatusRequest"
)

// Response `type` discriminators.
const (
	TypeNoWork    = "NoWork"
	TypeBuildWork = "BuildWork"
)

// PingRequest is the JSON body of POST /remoting/api/agent/ping.
type PingRequest struct {
	Type             string                     `json:"type"`
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
}

// GetWorkRequest is the JSON body of POST /remoting/api/agent/get_work.
type GetWorkRequest struct {
	Type             string                     `json:"type"`
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
}

// GetCookieRequest is the JSON body of POST /remoting/api/agent/get_cookie.
type GetCookieRequest struct {
	Type             string                     `json:"type"`
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
}

// IsIgnoredRequest is the JSON body of POST /remoting/api/agent/is_ignored.
type IsIgnoredRequest struct {
	Type             string                     `json:"type"`
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
	JobIdentifier    JobIdentifier              `json:"jobIdentifier"`
}

// ReportCurrentStatusRequest is the body of report_current_status.
type ReportCurrentStatusRequest struct {
	Type             string                     `json:"type"`
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
	JobIdentifier    JobIdentifier              `json:"jobIdentifier"`
	JobState         string                     `json:"jobState"`
}

// ReportCompleteStatusRequest is the body of report_completing / report_completed.
type ReportCompleteStatusRequest struct {
	Type             string                     `json:"type"`
	AgentRuntimeInfo *protocol.AgentRuntimeInfo `json:"agentRuntimeInfo"`
	JobIdentifier    JobIdentifier              `json:"jobIdentifier"`
	JobResult        string                     `json:"jobResult"`
}

// JobIdentifier names a build assignment the way the server understands it.
type JobIdentifier struct {
	PipelineName    string `json:"pipelineName"`
	PipelineCounter int    `json:"pipelineCounter"`
	PipelineLabel   string `json:"pipelineLabel"`
	StageName       string `json:"stageName"`
	BuildName       string `json:"buildName"`
	BuildID         int64  `json:"buildId"`
	StageCounter    string `json:"stageCounter"`
}

// Locator returns the slash-separated job locator
// (<pipeline>/<counter>/<stage>/<stageCounter>/<job>) used in console and
// artifact URLs.
func (j JobIdentifier) Locator() string {
	return fmt.Sprintf("%s/%d/%s/%s/%s",
		j.PipelineName, j.PipelineCounter, j.StageName, j.StageCounter, j.BuildName)
}

// Work is the JSON body of a get_work response. Type is either NoWork or BuildWork.
type Work struct {
	Type              string     `json:"type"`
	Assignment        Assignment `json:"assignment"`
	ConsoleLogCharset string     `json:"consoleLogCharset,omitempty"`
}

// Assignment carries everything the agent needs to execute one build.
type Assignment struct {
	FetchMaterials        bool              `json:"fetchMaterials"`
	CleanWorkingDirectory bool              `json:"cleanWorkingDirectory"`
	Builders              []Builder         `json:"builders"`
	ArtifactPlans         []json.RawMessage `json:"artifactPlans"`
	BuildWorkingDirectory Dir               `json:"buildWorkingDirectory"`
	JobIdentifier         JobIdentifier     `json:"jobIdentifier"`
	InitialContext        InitialContext    `json:"initialContext"`
	MaterialRevisions     json.RawMessage   `json:"materialRevisions"`
	Approver              string            `json:"approver,omitempty"`
}

// Builder is a single task in the assignment's build plan.
type Builder struct {
	Type        string   `json:"type"`
	Args        []string `json:"args"`
	Command     string   `json:"command"`
	WorkingDir  Dir      `json:"workingDir"`
	ErrorString string   `json:"errorString"`
	Description string   `json:"description"`
}

// Dir is a working-directory reference inside an assignment.
type Dir struct {
	Path string `json:"path"`
}

// InitialContext holds the environment properties the server exports for the job.
type InitialContext struct {
	Properties []Property `json:"properties"`
}

// Property is one environment variable (GO_PIPELINE_NAME, GO_STAGE_NAME, …).
type Property struct {
	Name   string `json:"name"`
	Value  string `json:"value"`
	Secure bool   `json:"secure"`
}
