// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0
// Task execution: exec (run command + args), compose (run subcommands in order).

package executor

import (
	"io"

	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

// Session is the execution context for running build commands (working dir, console, env, cancel).
type Session interface {
	WorkingDir() string
	Console() io.Writer
	Env() []string
	Canceled() bool
}

// Executor runs a single build command. Returns nil on success.
type Executor func(session Session, cmd *protocol.BuildCommand) error

// Registry returns executors by command name (e.g. "exec", "compose", "git").
func Registry() map[string]Executor {
	return map[string]Executor{
		protocol.CommandCompose: Compose,
		protocol.CommandExec:    Exec,
		protocol.CommandGit:     Git,
	}
}
