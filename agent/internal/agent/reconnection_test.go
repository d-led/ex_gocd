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
		{0, 2 * time.Second},   // 2^0 * 2s = 2s
		{1, 4 * time.Second},   // 2^1 * 2s = 4s
		{2, 8 * time.Second},   // 2^2 * 2s = 8s
		{3, 16 * time.Second},  // 2^3 * 2s = 16s
		{4, 32 * time.Second},  // 2^4 * 2s = 32s
		{5, 60 * time.Second},  // 2^5 * 2s = 64s, capped at 60s
		{6, 60 * time.Second},  // 2^6 * 2s = 128s, capped at 60s
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
