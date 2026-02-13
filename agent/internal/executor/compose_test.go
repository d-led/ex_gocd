// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package executor

import (
	"bytes"
	"os"
	"testing"

	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

type composeMockSession struct {
	*mockSession
	processed []string
}

func (c *composeMockSession) ProcessCommand(cmd *protocol.BuildCommand) error {
	if cmd != nil {
		c.processed = append(c.processed, cmd.Name)
	}
	if cmd != nil && cmd.Name == protocol.CommandExec {
		return Exec(c, cmd)
	}
	return nil
}

func TestCompose_RunsSubCommandsInOrder(t *testing.T) {
	dir := t.TempDir()
	buf := &bytes.Buffer{}
	mock := &mockSession{wd: dir, ConsoleBuf: buf, env: os.Environ()}
	session := &composeMockSession{mockSession: mock}

	cmd := &protocol.BuildCommand{
		Name: protocol.CommandCompose,
		SubCommands: []*protocol.BuildCommand{
			{Name: protocol.CommandExec, Command: "echo", Args: []string{"first"}},
			{Name: protocol.CommandExec, Command: "echo", Args: []string{"second"}},
		},
	}
	err := Compose(session, cmd)
	if err != nil {
		t.Fatalf("Compose: %v", err)
	}
	if len(session.processed) != 2 {
		t.Errorf("processed %d commands, want 2", len(session.processed))
	}
	out := buf.String()
	if out != "first\nsecond\n" && out != "first\r\nsecond\r\n" {
		t.Errorf("output = %q", out)
	}
}

func TestCompose_EmptySubCommandsSucceeds(t *testing.T) {
	session := &composeMockSession{mockSession: &mockSession{wd: t.TempDir(), ConsoleBuf: &bytes.Buffer{}, env: os.Environ()}}
	cmd := &protocol.BuildCommand{Name: protocol.CommandCompose, SubCommands: nil}
	err := Compose(session, cmd)
	if err != nil {
		t.Fatalf("Compose with nil SubCommands: %v", err)
	}
}
