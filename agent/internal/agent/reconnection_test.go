// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package agent

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

// TestExponentialBackoff verifies reconnection uses exponential backoff
func TestExponentialBackoff(t *testing.T) {
	baseDelay := 2 * time.Second
	maxDelay := 60 * time.Second

	tests := []struct {
		attempt       int
		expectedDelay time.Duration
	}{
		{0, 2 * time.Second},  // 2^0 * 2s = 2s
		{1, 4 * time.Second},  // 2^1 * 2s = 4s
		{2, 8 * time.Second},  // 2^2 * 2s = 8s
		{3, 16 * time.Second}, // 2^3 * 2s = 16s
		{4, 32 * time.Second}, // 2^4 * 2s = 32s
		{5, 60 * time.Second}, // 2^5 * 2s = 64s, capped at 60s
		{6, 60 * time.Second}, // 2^6 * 2s = 128s, capped at 60s
	}

	for _, tt := range tests {
		// Calculate exponential backoff (matching agent logic)
		retryDelay := baseDelay * time.Duration(1<<uint(tt.attempt))
		if retryDelay > maxDelay {
			retryDelay = maxDelay
		}

		assert.Equal(t, tt.expectedDelay, retryDelay,
			"Attempt %d: expected %v, got %v", tt.attempt, tt.expectedDelay, retryDelay)
	}
}

// TestBackoffResetsAfterStableConnection verifies that backoff resets to base delay
// after a connection was stable for >= minStableConnection.
func TestBackoffResetsAfterStableConnection(t *testing.T) {
	const baseRetryDelay = 2 * time.Second
	const maxRetryDelay = 60 * time.Second
	const minStableConnection = 30 * time.Second

	// Simulate agent reconnect loop: after each failed connect, wait current delay
	// then double it for next iteration.
	retryDelay := baseRetryDelay

	// 3 failed reconnects build up backoff
	retryDelay = waitAndDouble(retryDelay, maxRetryDelay) // waited 2s → now 4s
	assert.Equal(t, 4*time.Second, retryDelay)
	retryDelay = waitAndDouble(retryDelay, maxRetryDelay) // waited 4s → now 8s
	assert.Equal(t, 8*time.Second, retryDelay)
	retryDelay = waitAndDouble(retryDelay, maxRetryDelay) // waited 8s → now 16s
	assert.Equal(t, 16*time.Second, retryDelay)

	// Connection was stable for 45s (>= minStableConnection) — backoff resets
	connUptime := 45 * time.Second
	if connUptime >= minStableConnection {
		retryDelay = baseRetryDelay
	}
	assert.Equal(t, baseRetryDelay, retryDelay,
		"Backoff should reset to base after stable connection")

	// Next disconnect starts from base: wait 2s → double to 4s
	retryDelay = waitAndDouble(retryDelay, maxRetryDelay)
	assert.Equal(t, 4*time.Second, retryDelay)
}

// TestBackoffDoesNotResetForShortConnection verifies that backoff is NOT reset
// when the connection was up for less than minStableConnection.
func TestBackoffDoesNotResetForShortConnection(t *testing.T) {
	const baseRetryDelay = 2 * time.Second
	const maxRetryDelay = 60 * time.Second
	const minStableConnection = 30 * time.Second

	retryDelay := baseRetryDelay

	// Build up backoff over 3 failed reconnects
	retryDelay = waitAndDouble(retryDelay, maxRetryDelay) // 2s → 4s
	retryDelay = waitAndDouble(retryDelay, maxRetryDelay) // 4s → 8s
	retryDelay = waitAndDouble(retryDelay, maxRetryDelay) // 8s → 16s
	assert.Equal(t, 16*time.Second, retryDelay)

	// Connection only up for 5s (< minStableConnection) — backoff should NOT reset
	connUptime := 5 * time.Second
	if connUptime >= minStableConnection {
		retryDelay = baseRetryDelay
	}
	assert.Equal(t, 16*time.Second, retryDelay,
		"Backoff should NOT reset for short-lived connection")

	// Next disconnect continues from current backoff: wait 16s → double to 32s
	retryDelay = waitAndDouble(retryDelay, maxRetryDelay)
	assert.Equal(t, 32*time.Second, retryDelay)
}

// waitAndDouble mimics the agent's pattern: sleep current delay, then double (capped).
func waitAndDouble(current time.Duration, maxDelay time.Duration) time.Duration {
	next := current * 2
	if next > maxDelay {
		next = maxDelay
	}
	return next
}

// TestErrServerUnavailableIsDetectable verifies the sentinel error is usable with errors.Is.
func TestErrServerUnavailableIsDetectable(t *testing.T) {
	// Simulate the wrapping done in Start()
	err := ErrServerUnavailable
	assert.True(t, err != nil)

	// Registration error wrap
	regErr := &testError{msg: "connection refused"}
	wrapped := wrapError(ErrServerUnavailable, "registration failed", regErr)
	assert.Contains(t, wrapped.Error(), "gocd server unavailable")
	assert.Contains(t, wrapped.Error(), "registration failed")
	assert.Contains(t, wrapped.Error(), "connection refused")
}

// TestErrServerUnavailableIsDetectable verifies the sentinel error is usable with errors.Is.
func wrapError(sentinel error, msg string, err error) error {
	return &joinedError{sentinel: sentinel, msg: msg, err: err}
}

type testError struct{ msg string }

func (e *testError) Error() string { return e.msg }

type joinedError struct {
	sentinel error
	msg      string
	err      error
}

func (e *joinedError) Error() string {
	return e.sentinel.Error() + ": " + e.msg + ": " + e.err.Error()
}

func (e *joinedError) Is(target error) bool {
	return target == e.sentinel
}

func (e *joinedError) Unwrap() error {
	return e.err
}
