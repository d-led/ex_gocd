// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

// Package telemetry sets up OpenTelemetry tracing for the GoCD agent.
// Spans are exported via OTLP HTTP to the collector (default localhost:4318)
// which forwards to Jaeger (http://localhost:16686).
//
// The agent extracts W3C traceparent from server build payloads so agent-side
// spans nest under the server's pipeline.trigger → scheduler.enqueue trace.
//
// Env vars:
//
//	OTEL_EXPORTER_OTLP_ENDPOINT  — collector URL (default http://localhost:4318)
//	OTEL_SERVICE_NAME            — service name in Jaeger (default gocd-agent)
//	OTEL_TRACES_EXPORTER         — "otlp" to enable, anything else disables
package telemetry

import (
	"context"
	"fmt"
	"os"

	agentlog "github.com/d-led/ex_gocd/agent/internal/log"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// Setup initialises the OpenTelemetry SDK and returns a shutdown function.
// Safe no-op when OTEL_TRACES_EXPORTER is not "otlp" or the collector is
// unavailable — the agent works fine without tracing.
func Setup() (shutdown func(context.Context) error) {
	noop := func(_ context.Context) error { return nil }

	if os.Getenv("OTEL_TRACES_EXPORTER") != "otlp" {
		agentlog.Logger.Debug().Msg("OTEL_TRACES_EXPORTER is not 'otlp' — tracing disabled")
		return noop
	}

	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "localhost:4318"
	}

	svcName := os.Getenv("OTEL_SERVICE_NAME")
	if svcName == "" {
		svcName = "gocd-agent"
	}

	hostname, _ := os.Hostname()

	exp, err := otlptracehttp.New(context.Background(),
		otlptracehttp.WithEndpoint(endpoint),
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		agentlog.Logger.Warn().Err(err).Msg("OTel exporter setup failed — tracing disabled")
		return noop
	}

	res, err := resource.New(context.Background(),
		resource.WithAttributes(
			semconv.ServiceName(svcName),
			semconv.HostName(hostname),
		),
	)
	if err != nil {
		agentlog.Logger.Warn().Err(err).Msg("OTel resource creation failed")
		res = resource.Default()
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp),
		sdktrace.WithResource(res),
	)

	// Set global propagator so traceparent extraction/injection works
	otel.SetTextMapPropagator(propagation.TraceContext{})
	otel.SetTracerProvider(tp)

	agentlog.Logger.Info().
		Str("endpoint", endpoint).
		Str("service", svcName).
		Str("hostname", hostname).
		Msg("OTel tracing enabled")

	return func(ctx context.Context) error {
		if err := tp.Shutdown(ctx); err != nil {
			return fmt.Errorf("OTel shutdown: %w", err)
		}
		return nil
	}
}
