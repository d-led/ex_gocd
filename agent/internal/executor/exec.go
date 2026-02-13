// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package executor

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

// Exec runs Command with Args in session's working dir, stdout/stderr to console.
func Exec(session Session, cmd *protocol.BuildCommand) error {
	if cmd.Command == "" {
		return fmt.Errorf("exec: command is required")
	}
	args := cmd.Args
	if args == nil {
		args = []string{}
	}
	c := exec.Command(cmd.Command, args...)
	c.Dir = session.WorkingDir()
	c.Env = session.Env()
	c.Stdout = session.Console()
	c.Stderr = session.Console()

	if err := c.Start(); err != nil {
		return fmt.Errorf("exec start: %w", err)
	}

	done := make(chan error, 1)
	go func() { done <- c.Wait() }()

	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case err := <-done:
			if err != nil {
				return fmt.Errorf("exec: %w", err)
			}
			return nil
		case <-ticker.C:
			if session.Canceled() {
				_ = c.Process.Kill()
				<-done
				return fmt.Errorf("exec: canceled")
			}
		}
	}
}

// WorkingDir returns the absolute working directory for this command (session root + cmd.WorkingDir).
func WorkingDir(sessionRoot, cmdWorkingDir string) string {
	if cmdWorkingDir == "" {
		return sessionRoot
	}
	return filepath.Clean(filepath.Join(sessionRoot, cmdWorkingDir))
}
