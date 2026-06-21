// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package telemetry

import (
	"context"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

// ParentContextFromTraceParent extracts a parent span context from the
// W3C traceparent header embedded in the build payload by the server.
// Returns the background context unchanged if traceparent is empty.
func ParentContextFromTraceParent(ctx context.Context, traceParent, traceState string) context.Context {
	if traceParent == "" {
		return ctx
	}

	carrier := propagation.MapCarrier{
		"traceparent": traceParent,
	}
	if traceState != "" {
		carrier["tracestate"] = traceState
	}

	return otel.GetTextMapPropagator().Extract(ctx, carrier)
}
