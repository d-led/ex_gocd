// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package executor

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

func TestGit_Clone(t *testing.T) {
	// Use a small public repo; shallow clone for speed
	dir := t.TempDir()
	buf := &bytes.Buffer{}
	session := &mockSession{
		wd:         dir,
		ConsoleBuf: buf,
		env:        os.Environ(),
	}
	cmd := &protocol.BuildCommand{
		Name:   protocol.CommandGit,
		URL:    "https://github.com/golang/example.git",
		Branch: "master",
		Dest:   "example",
	}
	err := Git(session, cmd)
	if err != nil {
		t.Skipf("git clone (network): %v", err)
	}
	head := filepath.Join(dir, "example", ".git", "HEAD")
	if _, err := os.Stat(head); err != nil {
		t.Errorf("clone did not create repo: %v", err)
	}
}

func TestGit_EmptyURLFails(t *testing.T) {
	session := &mockSession{wd: t.TempDir(), ConsoleBuf: &bytes.Buffer{}, env: os.Environ()}
	cmd := &protocol.BuildCommand{Name: protocol.CommandGit, URL: ""}
	err := Git(session, cmd)
	if err == nil {
		t.Error("Git with empty URL should fail")
	}
}
