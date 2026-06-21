// Copyright © 2026 ex_gocd
// Licensed under the Apache License, Version 2.0

package log

import (
	"context"
	"runtime"
	"time"

	"github.com/rs/zerolog"
)

// StartRuntimeMetrics periodically logs Go runtime stats (goroutines, memory, GC).
// Call from agent startup; returns a stop function.
func StartRuntimeMetrics(ctx context.Context, log *zerolog.Logger, interval time.Duration) (stop func()) {
	done := make(chan struct{})

	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		var m runtime.MemStats
		for {
			select {
			case <-done:
				return
			case <-ctx.Done():
				return
			case <-ticker.C:
				runtime.ReadMemStats(&m)
				log.Debug().
					Int("goroutines", runtime.NumGoroutine()).
					Uint64("heap_alloc_mb", m.HeapAlloc/1024/1024).
					Uint64("heap_sys_mb", m.HeapSys/1024/1024).
					Uint64("total_alloc_mb", m.TotalAlloc/1024/1024).
					Uint32("num_gc", m.NumGC).
					Uint64("gc_pause_ns", m.PauseNs[(m.NumGC+255)%256]).
					Msg("runtime metrics")
			}
		}
	}()

	return func() { close(done) }
}
