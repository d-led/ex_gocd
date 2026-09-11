// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package remoting

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fixture loads a captured protocol fixture from the server project. The path
// is relative to this package; the fixture is the single source of truth for
// the wire contract (see test/fixtures/remoting/README.md).
func fixture(t *testing.T, name string) []byte {
	t.Helper()
	path := filepath.Join("..", "..", "..", "test", "fixtures", "remoting", name)
	data, err := os.ReadFile(path)
	require.NoErrorf(t, err, "fixture %s not found at %s", name, path)
	return data
}

func TestDecodeBuildWorkFromCapture(t *testing.T) {
	var work Work
	require.NoError(t, json.Unmarshal(fixture(t, "build_work_response.json"), &work))

	assert.Equal(t, TypeBuildWork, work.Type)
	assert.Equal(t, "UTF-8", work.ConsoleLogCharset)

	job := work.Assignment.JobIdentifier
	assert.Equal(t, "capture-protocol", job.PipelineName)
	assert.Equal(t, 3, job.PipelineCounter)
	assert.Equal(t, "probe", job.StageName)
	assert.Equal(t, "1", job.StageCounter)
	assert.Equal(t, "probe-job", job.BuildName)
	assert.Equal(t, int64(35), job.BuildID)
	assert.Equal(t, "capture-protocol/3/probe/1/probe-job", job.Locator())

	assert.Equal(t, "pipelines/capture-protocol", work.Assignment.BuildWorkingDirectory.Path)
	assert.Len(t, work.Assignment.Builders, 1)
	builder := work.Assignment.Builders[0]
	assert.Equal(t, "CommandBuilderWithArgList", builder.Type)
	assert.Equal(t, "echo", builder.Command)
	assert.Equal(t, []string{"capture-me"}, builder.Args)

	// GO_* environment variables are present and parsed.
	props := work.Assignment.InitialContext.Properties
	names := make(map[string]string, len(props))
	for _, p := range props {
		names[p.Name] = p.Value
	}
	assert.Equal(t, "capture-protocol", names["GO_PIPELINE_NAME"])
	assert.Equal(t, "3", names["GO_PIPELINE_COUNTER"])
	assert.Equal(t, "probe", names["GO_STAGE_NAME"])
	assert.Equal(t, "probe-job", names["GO_JOB_NAME"])
}

func TestDecodeNoWork(t *testing.T) {
	var work Work
	require.NoError(t, json.Unmarshal(fixture(t, "no_work_response.json"), &work))
	assert.Equal(t, TypeNoWork, work.Type)
}
