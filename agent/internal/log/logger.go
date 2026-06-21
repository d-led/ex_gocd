// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

// Package log provides a shared zerolog logger for all agent packages.
// Dual output: human-readable console (stderr) + JSON to file for Fluent Bit → Loki.
package log

import (
	"io"
	"os"
	"time"

	"github.com/rs/zerolog"
)

// Logger is the global agent logger. All packages should use this.
var Logger zerolog.Logger

func init() {
	logFile := "/tmp/ex_gocd_agent.log"
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		f = nil // fallback: console only
	}

	consoleWriter := zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: time.RFC3339}
	var writers []io.Writer
	writers = append(writers, consoleWriter)
	if f != nil {
		writers = append(writers, f)
	}
	multi := zerolog.MultiLevelWriter(writers...)
	Logger = zerolog.New(multi).With().Timestamp().Str("component", "agent").Logger()
}

// Hostname returns the machine hostname.
func Hostname() string {
	h, _ := os.Hostname()
	return h
}
