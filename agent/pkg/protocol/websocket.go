// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0
// Protocol based on github.com/gocd-contrib/gocd-golang-agent

package protocol

import (
	"encoding/json"
)

// Protocol Action constants
const (
	SetCookieAction           = "setCookie"
	CancelBuildAction         = "cancelBuild"
	ReregisterAction          = "reregister"
	BuildAction               = "build"
	PingAction                = "ping"
	AckAction                 = "acknowledge"
	ReportCurrentStatusAction = "reportCurrentStatus"
	ReportCompletingAction    = "reportCompleting"
	ReportCompletedAction     = "reportCompleted"
)

// Message is the base protocol message for WebSocket communication
type Message struct {
	Action      string          `json:"action"`
	Data        json.RawMessage `json:"data,omitempty"`
	AckId       string          `json:"ackId,omitempty"`
	MessageType string          `json:"messageType,omitempty"`
}

// AgentIdentifier uniquely identifies an agent
type AgentIdentifier struct {
	HostName  string `json:"hostName"`
	IpAddress string `json:"ipAddress"`
	Uuid      string `json:"uuid"`
}

// AgentBuildingInfo contains current build information
type AgentBuildingInfo struct {
	BuildingInfo string `json:"buildingInfo"`
	BuildLocator string `json:"buildLocator"`
}

// AgentRuntimeInfo contains agent status and runtime information
type AgentRuntimeInfo struct {
	Identifier                   *AgentIdentifier   `json:"identifier"`
	BuildingInfo                 *AgentBuildingInfo `json:"buildingInfo"`
	RuntimeStatus                string             `json:"runtimeStatus"` // "Idle", "Building", etc.
	Location                     string             `json:"location"`
	UsableSpace                  int64              `json:"usableSpace"`
	OperatingSystemName          string             `json:"operatingSystemName"`
	Cookie                       string             `json:"cookie,omitempty"`
	AgentLauncherVersion         string             `json:"agentLauncherVersion,omitempty"`
	ElasticPluginId              string             `json:"elasticPluginId,omitempty"`
	ElasticAgentId               string             `json:"elasticAgentId,omitempty"`
	SupportsBuildCommandProtocol bool               `json:"supportsBuildCommandProtocol"`
}

// Build represents a job to execute
type Build struct {
	BuildId                 string         `json:"buildId"`
	BuildLocator            string         `json:"buildLocator"`
	BuildLocatorForDisplay  string         `json:"buildLocatorForDisplay"`
	ConsoleUrl              string         `json:"consoleURI"`
	ArtifactUploadBaseUrl   string         `json:"artifactUploadBaseUrl"`
	PropertyBaseUrl         string         `json:"propertyBaseUrl,omitempty"`
	BuildCommand            *BuildCommand  `json:"buildCommand"`
}

// BuildCommand contains the tasks to execute
type BuildCommand struct {
	Name         string                   `json:"name"`
	SubCommands  []*BuildCommand          `json:"subCommands,omitempty"`
	RunIf        string                   `json:"runIfConfig,omitempty"`
	OnCancelCmd  *BuildCommand            `json:"onCancelCommand,omitempty"`
	WorkingDir   string                   `json:"workingDirectory,omitempty"`
	Command      string                   `json:"command,omitempty"`
	Args         []string                 `json:"args,omitempty"`
	Test         map[string]string        `json:"test,omitempty"`
	Src          string                   `json:"src,omitempty"`
	Dest         string                   `json:"dest,omitempty"`
	URL          string                   `json:"url,omitempty"`
	Branch       string                   `json:"branch,omitempty"`
	Attributes   map[string]interface{}   `json:"attributes,omitempty"`
}

// Report contains job execution status  
type Report struct {
	BuildId          string            `json:"buildId"`
	Result           string            `json:"result,omitempty"` // "Passed", "Failed", "Cancelled"
	JobState         string            `json:"jobState,omitempty"`
	AgentRuntimeInfo *AgentRuntimeInfo `json:"agentRuntimeInfo"`
}

// Registration response from server
type Registration struct {
	AgentPrivateKey  string `json:"agentPrivateKey,omitempty"`
	AgentCertificate string `json:"agentCertificate,omitempty"`
}

// Helper methods to extract typed data from Message

func (m *Message) AgentRuntimeInfo() *AgentRuntimeInfo {
	var info AgentRuntimeInfo
	json.Unmarshal(m.Data, &info)
	return &info
}

func (m *Message) DataBuild() *Build {
	var build Build
	json.Unmarshal(m.Data, &build)
	return &build
}

func (m *Message) Report() *Report {
	var report Report
	json.Unmarshal(m.Data, &report)
	return &report
}

func (m *Message) DataString() string {
	var s string
	json.Unmarshal(m.Data, &s)
	return s
}

// Message constructors

func PingMessage(info *AgentRuntimeInfo) *Message {
	data, _ := json.Marshal(info)
	return &Message{
		Action: PingAction,
		Data:   data,
	}
}

func AckMessage(ackId string) *Message {
	return &Message{
		Action: AckAction,
		AckId:  ackId,
	}
}

func ReportMessage(action string, report *Report) *Message {
	data, _ := json.Marshal(report)
	return &Message{
		Action: action,
		Data:   data,
	}
}

func ReportCompletedMessage(report *Report) *Message {
	return ReportMessage(ReportCompletedAction, report)
}

func ReportCompletingMessage(report *Report) *Message {
	return ReportMessage(ReportCompletingAction, report)
}

func ReportCurrentStatusMessage(report *Report) *Message {
	return ReportMessage(ReportCurrentStatusAction, report)
}
