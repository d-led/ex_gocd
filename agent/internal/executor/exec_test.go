// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package executor

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

type mockSession struct {
	wd       string
	ConsoleBuf *bytes.Buffer
	env      []string
	canceled bool
}

func (m *mockSession) WorkingDir() string    { return m.wd }
func (m *mockSession) Console() io.Writer    { return m.ConsoleBuf }
func (m *mockSession) Env() []string        { return m.env }
func (m *mockSession) Canceled() bool       { return m.canceled }

func TestWorkingDir(t *testing.T) {
	root := "/tmp/build"
	if filepath.Separator == '\\' {
		root = `C:\build`
	}
	tests := []struct {
		cmdDir string
		want   string
	}{
		{"", root},
		{"sub", filepath.Join(root, "sub")},
		{"nested/dir", filepath.Join(root, "nested", "dir")},
	}
	for _, tt := range tests {
		got := WorkingDir(root, tt.cmdDir)
		if got != tt.want {
			t.Errorf("WorkingDir(%q, %q) = %q, want %q", root, tt.cmdDir, got, tt.want)
		}
	}
}

func TestExec_RunEcho(t *testing.T) {
	dir := t.TempDir()
	buf := &bytes.Buffer{}
	session := &mockSession{
		wd:         dir,
		ConsoleBuf: buf,
		env:        []string{"PATH=" + os.Getenv("PATH")},
	}
	cmd := &protocol.BuildCommand{
		Name:    protocol.CommandExec,
		Command: "echo",
		Args:    []string{"hello", "world"},
	}
	err := Exec(session, cmd)
	if err != nil {
		t.Fatalf("Exec: %v", err)
	}
	out := buf.String()
	if out != "hello world\n" && out != "hello world\r\n" {
		t.Errorf("console output = %q, want hello world newline", out)
	}
}

func TestExec_EmptyCommandFails(t *testing.T) {
	session := &mockSession{wd: t.TempDir(), ConsoleBuf: &bytes.Buffer{}, env: os.Environ()}
	cmd := &protocol.BuildCommand{Name: protocol.CommandExec, Command: ""}
	err := Exec(session, cmd)
	if err == nil {
		t.Error("Exec with empty command should fail")
	}
}

func TestExec_NoSuchCommandFails(t *testing.T) {
	session := &mockSession{wd: t.TempDir(), ConsoleBuf: &bytes.Buffer{}, env: os.Environ()}
	cmd := &protocol.BuildCommand{Name: protocol.CommandExec, Command: "/nonexistent/binary/xyz"}
	err := Exec(session, cmd)
	if err == nil {
		t.Error("Exec with nonexistent command should fail")
	}
}
