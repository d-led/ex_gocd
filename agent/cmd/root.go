// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package cmd

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/d-led/ex_gocd/agent/internal/agent"
	"github.com/d-led/ex_gocd/agent/internal/config"
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "gocd-agent",
	Short: "GoCD Agent - Execute CI/CD jobs",
	Long: `A modern GoCD agent written in Go that executes CI/CD jobs.

Features:
  - Automatic registration with GoCD server
  - Git operations using go-git (no git CLI required)
  - Task execution (exec, git, artifacts)
  - Console log streaming
  - Graceful shutdown
  
The agent is configured via environment variables following 12-factor app principles.`,
	Run: runAgent,
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func runAgent(cmd *cobra.Command, args []string) {
	if err := RunAgent(); err != nil {
		fmt.Fprintf(os.Stderr, "Agent error: %v\n", err)
		os.Exit(1)
	}
}

// RunAgent starts and runs the agent, blocking until shutdown or error.
// Returns nil on clean shutdown, error otherwise.
// Exported for use by main.go's restart-with-panic-recovery loop.
func RunAgent() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	agt, err := agent.New(cfg)
	if err != nil {
		return fmt.Errorf("failed to create agent: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(sigChan)

	errChan := make(chan error, 1)
	go func() {
		defer func() {
			if r := recover(); r != nil {
				slog.Error("agent goroutine panicked",
					"panic", fmt.Sprintf("%v", r),
				)
				errChan <- fmt.Errorf("agent goroutine panicked: %v", r)
			}
		}()
		errChan <- agt.Start(ctx)
	}()

	select {
	case sig := <-sigChan:
		slog.Info("received shutdown signal, stopping agent", "signal", sig.String())
		cancel()
		return <-errChan

	case err := <-errChan:
		if err != nil {
			return fmt.Errorf("agent error: %w", err)
		}
		return nil
	}
}

func init() {
	// No flags needed - everything is configured via environment variables
}
