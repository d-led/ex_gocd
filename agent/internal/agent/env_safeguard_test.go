package agent

import (
	"testing"
)

func TestIsDangerousEnvVar(t *testing.T) {
	dangerous := []string{
		"LD_PRELOAD", "ld_preload",
		"LD_LIBRARY_PATH",
		"DYLD_INSERT_LIBRARIES",
		"DYLD_LIBRARY_PATH",
		"PYTHONPATH",
		"PYTHONSTARTUP",
		"PYTHONOPTIMIZE",
		"PERL5LIB", "PERLLIB",
		"RUBYLIB", "RUBYOPT",
		"GEM_PATH", "GEM_HOME",
		"NODE_PATH", "NODE_OPTIONS",
		"CLASSPATH",
		"JAVA_TOOL_OPTIONS", "JAVA_OPTIONS", "_JAVA_OPTIONS",
		"GOPATH",
	}
	for _, v := range dangerous {
		if !isDangerousEnvVar(v) {
			t.Errorf("expected %q to be dangerous", v)
		}
	}

	safe := []string{
		"PATH", "HOME", "USER", "SHELL",
		"MIX_ENV", "RAILS_ENV",
		"OTEL_EXPORTER_OTLP_ENDPOINT",
		"MY_CUSTOM_VAR", "", "FOO",
	}
	for _, v := range safe {
		if isDangerousEnvVar(v) {
			t.Errorf("expected %q to be safe", v)
		}
	}
}
