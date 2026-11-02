package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// readPid returns what the pidfile holds.
func readPid(t *testing.T, path string) int {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("pidfile unreadable: %v", err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatalf("pidfile does not hold a pid: %v", err)
	}
	return pid
}

func TestWritePidFileWritesThePid(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.pid")

	if err := writePidFile(path, os.Getpid()); err != nil {
		t.Fatalf("writePidFile: %v", err)
	}

	if got := readPid(t, path); got != os.Getpid() {
		t.Fatalf("pidfile holds %d, want %d", got, os.Getpid())
	}
}

func TestWritePidFileReplacesAStaleOne(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.pid")
	// A pid nothing runs: the process that wrote it is gone.
	if err := os.WriteFile(path, []byte("0\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := writePidFile(path, os.Getpid()); err != nil {
		t.Fatalf("writePidFile over a stale pidfile: %v", err)
	}

	if got := readPid(t, path); got != os.Getpid() {
		t.Fatalf("pidfile holds %d, want %d", got, os.Getpid())
	}
}

// A container restart leaves a pidfile naming PID 1, and the agent is PID 1
// again — it must recognise its own pidfile rather than refuse to start.
func TestWritePidFileReplacesItsOwnPid(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.pid")
	if err := os.WriteFile(path, []byte(strconv.Itoa(os.Getpid())+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := writePidFile(path, os.Getpid()); err != nil {
		t.Fatalf("writePidFile over its own pidfile: %v", err)
	}
}

func TestWritePidFileRefusesWhileAnotherAgentRuns(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.pid")
	// The test's parent is alive and is not this process.
	other := os.Getppid()
	if err := os.WriteFile(path, []byte(strconv.Itoa(other)+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	err := writePidFile(path, os.Getpid())

	if err == nil {
		t.Fatalf("writePidFile accepted a pidfile held by live pid %d", other)
	}
	if got := readPid(t, path); got != other {
		t.Fatalf("a refused start changed the pidfile to %d", got)
	}
}
