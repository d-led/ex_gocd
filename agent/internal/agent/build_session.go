// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0
// BuildSession runs a single build: create work dir, run command tree, report status, upload console.

package agent

import (
	"fmt"
	"io"
	"log"
	"os"
	"strings"

	"github.com/d-led/ex_gocd/agent/internal/executor"
	"github.com/d-led/ex_gocd/agent/pkg/protocol"
)

// Ensure BuildSession implements executor.ComposeSession (ProcessCommand).
var _ executor.ComposeSession = (*BuildSession)(nil)

const (
	buildPassed   = "Passed"
	buildFailed   = "Failed"
	buildCanceled = "Cancelled"
)

// BuildSession runs the build command tree and reports status.
type BuildSession struct {
	buildID     string
	rootDir     string
	wd          string
	command     *protocol.BuildCommand
	console     io.WriteCloser
	send        func(*protocol.Message)
	getReport   func(buildID, jobState, result string) *protocol.Report
	canceled    func() bool
	executors   map[string]executor.Executor
	buildResult string
}

// NewBuildSessionWithConsole creates a build session with an already-created console writer.
func NewBuildSessionWithConsole(buildID string, command *protocol.BuildCommand, rootDir string, consoleWriter io.WriteCloser, send func(*protocol.Message), getReport func(buildID, jobState, result string) *protocol.Report, canceled func() bool) *BuildSession {
	return &BuildSession{
		buildID:     buildID,
		rootDir:     rootDir,
		wd:          rootDir,
		command:     command,
		console:     consoleWriter,
		send:        send,
		getReport:   getReport,
		canceled:    canceled,
		executors:   executor.Registry(),
		buildResult: buildPassed,
	}
}

func sanitizeDir(s string) string {
	s = strings.ReplaceAll(s, "/", "_")
	s = strings.ReplaceAll(s, "\\", "_")
	if s == "" {
		s = "default"
	}
	return s
}

// Run executes the build command tree, reports status, and closes the console.
func (s *BuildSession) Run() {
	defer func() {
		if c, ok := s.console.(interface{ Close() error }); ok {
			c.Close()
		}
	}()

	log.Printf("Build %s started, root: %s", s.buildID, s.rootDir)
	s.send(protocol.ReportCurrentStatusMessage(s.getReport(s.buildID, "Building", "")))

	err := s.ProcessCommand(s.command)
	if s.canceled != nil && s.canceled() {
		s.buildResult = buildCanceled
	} else if err != nil {
		s.buildResult = buildFailed
		log.Printf("Build %s failed: %v", s.buildID, err)
	}

	s.send(protocol.ReportCompletingMessage(s.getReport(s.buildID, "Completing", "")))
	s.send(protocol.ReportCompletedMessage(s.getReport(s.buildID, "Completed", s.buildResult)))
	log.Printf("Build %s completed: %s", s.buildID, s.buildResult)
}

// ProcessCommand runs a single command (exec or compose). Implements executor.ComposeSession.
func (s *BuildSession) ProcessCommand(cmd *protocol.BuildCommand) error {
	if cmd == nil {
		return nil
	}
	if s.canceled != nil && s.canceled() {
		return fmt.Errorf("build canceled")
	}
	s.wd = executor.WorkingDir(s.rootDir, cmd.WorkingDir)
	if err := s.ensureWorkDir(); err != nil {
		return err
	}
	execFn := s.executors[cmd.Name]
	if execFn == nil {
		return fmt.Errorf("unknown command: %s", cmd.Name)
	}
	return execFn(s, cmd)
}

// WorkingDir implements executor.Session.
func (s *BuildSession) WorkingDir() string { return s.wd }

// Console implements executor.Session.
func (s *BuildSession) Console() io.Writer { return s.console }

// Env returns environment for child processes (current env; can add build-specific later).
func (s *BuildSession) Env() []string {
	return envFromDir(s.wd)
}

func envFromDir(dir string) []string {
	return append(os.Environ(), "PWD="+dir)
}

// Canceled implements executor.Session.
func (s *BuildSession) Canceled() bool {
	if s.canceled == nil {
		return false
	}
	return s.canceled()
}

func (s *BuildSession) ensureWorkDir() error {
	return os.MkdirAll(s.wd, 0755)
}
