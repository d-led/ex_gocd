// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package remoting

import (
	"strconv"

	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

// Build converts a BuildWork assignment into the protocol.Build the executor
// consumes. The agent fills in the URLs the Java agent computes itself: the
// official BuildWork carries no consoleURI or artifactUploadBaseUrl.
func (c *Client) Build(work *Work) *protocol.Build {
	job := work.Assignment.JobIdentifier

	build := &protocol.Build{
		BuildId:                strconv.FormatInt(job.BuildID, 10),
		BuildLocator:           job.Locator(),
		BuildLocatorForDisplay: job.Locator(),
		ConsoleUrl:             c.consoleLogURL(job),
		ArtifactUploadBaseUrl:  c.filesURL(job),
	}

	root := &protocol.BuildCommand{
		Name:       "compose",
		WorkingDir: work.Assignment.BuildWorkingDirectory.Path,
	}

	// The server exports environment variables as initialContext.properties.
	// The executor picks these up as `export` nodes, exactly like the ExGoCD
	// server's own BuildWork encode.
	for _, p := range work.Assignment.InitialContext.Properties {
		root.SubCommands = append(root.SubCommands, &protocol.BuildCommand{
			Name:       "export",
			Args:       []string{p.Name, p.Value},
			Attributes: map[string]interface{}{"name": p.Name, "value": p.Value, "secure": p.Secure},
		})
	}

	// Each non-empty builder becomes an `exec` node. GoCD defaults a task's
	// working directory to the build working directory, so commands that don't
	// declare their own directory inherit the root's.
	for _, b := range work.Assignment.Builders {
		if b.Command == "" {
			continue // cancel/null builders have no executable command
		}
		root.SubCommands = append(root.SubCommands, &protocol.BuildCommand{
			Name:    "exec",
			Command: b.Command,
			Args:    b.Args,
		})
	}

	build.BuildCommand = root
	return build
}
