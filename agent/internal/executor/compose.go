// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0
// Compose runs SubCommands in order; fails fast on first error.

package executor

import (
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

// Compose runs each subcommand in sequence. Session must support ProcessCommand.
type ComposeSession interface {
	Session
	ProcessCommand(cmd *protocol.BuildCommand) error
}

// Compose runs SubCommands in order.
func Compose(session Session, cmd *protocol.BuildCommand) error {
	cs, ok := session.(ComposeSession)
	if !ok {
		return nil
	}
	for _, sub := range cmd.SubCommands {
		if sub == nil {
			continue
		}
		if cs.Canceled() {
			break
		}
		if err := cs.ProcessCommand(sub); err != nil {
			return err
		}
	}
	return nil
}
