// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0
// Git executor: clone URL into Dest, checkout Branch if set. Uses git binary.

package executor

import (
	"fmt"
	"os/exec"
	"path/filepath"

	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

// Git runs git clone (and optionally checkout) so the agent can run git material / checkout jobs.
func Git(session Session, cmd *protocol.BuildCommand) error {
	url := cmd.URL
	if url == "" {
		return fmt.Errorf("git: url is required")
	}
	dest := cmd.Dest
	if dest == "" {
		dest = "."
	}
	destPath := filepath.Join(session.WorkingDir(), dest)

	// git clone [--branch branch] url dest
	args := []string{"clone"}
	if cmd.Branch != "" {
		args = append(args, "--branch", cmd.Branch)
	}
	args = append(args, url, destPath)

	c := exec.Command("git", args...)
	c.Dir = session.WorkingDir()
	c.Env = session.Env()
	c.Stdout = session.Console()
	c.Stderr = session.Console()
	if err := c.Run(); err != nil {
		return fmt.Errorf("git clone: %w", err)
	}
	return nil
}
