// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package cmd

import (
	"context"
	"fmt"
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
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
		os.Exit(1)
	}

	// Create agent
	agt, err := agent.New(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create agent: %v\n", err)
		os.Exit(1)
	}

	// Setup context with cancellation
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	// Start agent in goroutine
	errChan := make(chan error, 1)
	go func() {
		errChan <- agt.Start(ctx)
	}()

	// Wait for shutdown signal or error
	select {
	case <-sigChan:
		fmt.Println("\nReceived shutdown signal, stopping...")
		cancel()
		// Wait for agent to stop
		<-errChan

	case err := <-errChan:
		if err != nil {
			fmt.Fprintf(os.Stderr, "Agent error: %v\n", err)
			os.Exit(1)
		}
	}

	fmt.Println("Agent stopped")
}

func init() {
	// No flags needed - everything is configured via environment variables
}
