// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

// Package protocol holds the domain types shared by the agent's transport and
// its build executor. The wire-specific request/response envelopes live in the
// transport packages (internal/remoting).
package protocol

// AgentIdentifier uniquely identifies an agent.
type AgentIdentifier struct {
	HostName  string `json:"hostName"`
	IpAddress string `json:"ipAddress"`
	Uuid      string `json:"uuid"`
}

// AgentBuildingInfo describes the build an agent is currently working on.
type AgentBuildingInfo struct {
	BuildingInfo string `json:"buildingInfo"`
	BuildLocator string `json:"buildLocator"`
}

// AgentRuntimeInfo is the agent's self-description, reported on every remoting
// call. Field names and `type: "AgentRuntimeInfo"` mirror GoCD's
// com.thoughtworks.go.server.service.AgentRuntimeInfo serialization.
type AgentRuntimeInfo struct {
	Type                         string             `json:"type"`
	Identifier                   *AgentIdentifier   `json:"identifier"`
	BuildingInfo                 *AgentBuildingInfo `json:"buildingInfo"`
	RuntimeStatus                string             `json:"runtimeStatus"` // "Idle", "Building", etc.
	Location                     string             `json:"location"`
	UsableSpace                  int64              `json:"usableSpace"`
	OperatingSystemName          string             `json:"operatingSystemName"`
	Cookie                       string             `json:"cookie,omitempty"`
	AgentBootstrapperVersion     string             `json:"agentBootstrapperVersion,omitempty"`
	AgentVersion                 string             `json:"agentVersion,omitempty"`
	AgentLauncherVersion         string             `json:"agentLauncherVersion,omitempty"`
	ElasticPluginId              string             `json:"elasticPluginId,omitempty"`
	ElasticAgentId               string             `json:"elasticAgentId,omitempty"`
	SupportsBuildCommandProtocol bool               `json:"supportsBuildCommandProtocol"`
}

// Build represents a job to execute.
type Build struct {
	BuildId                string        `json:"buildId"`
	BuildLocator           string        `json:"buildLocator"`
	BuildLocatorForDisplay string        `json:"buildLocatorForDisplay"`
	ConsoleUrl             string        `json:"consoleURI"`
	ArtifactUploadBaseUrl  string        `json:"artifactUploadBaseUrl"`
	PropertyBaseUrl        string        `json:"propertyBaseUrl,omitempty"`
	BuildCommand           *BuildCommand `json:"buildCommand"`
	// W3C Trace Context — injected by the ExGoCD server for cross-process tracing.
	TraceParent string `json:"traceparent,omitempty"`
	TraceState  string `json:"tracestate,omitempty"`
}

// BuildCommand is a node in the executable command tree.
type BuildCommand struct {
	Name        string                 `json:"name"`
	SubCommands []*BuildCommand        `json:"subCommands,omitempty"`
	RunIf       string                 `json:"runIfConfig,omitempty"`
	OnCancelCmd *BuildCommand          `json:"onCancelCommand,omitempty"`
	WorkingDir  string                 `json:"workingDirectory,omitempty"`
	Command     string                 `json:"command,omitempty"`
	Args        []string               `json:"args,omitempty"`
	Test        map[string]string      `json:"test,omitempty"`
	Src         string                 `json:"src,omitempty"`
	Dest        string                 `json:"dest,omitempty"`
	URL         string                 `json:"url,omitempty"`
	Branch      string                 `json:"branch,omitempty"`
	Attributes  map[string]interface{} `json:"attributes,omitempty"`
}

// Registration is the response body of a successful agent registration.
type Registration struct {
	AgentPrivateKey  string `json:"agentPrivateKey,omitempty"`
	AgentCertificate string `json:"agentCertificate,omitempty"`
}
