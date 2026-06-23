defmodule ExGoCD.MockData do
  @moduledoc """
  Mock data for development and testing without database dependencies.

  Provides realistic GoCD pipeline data that can be used to develop and test
  the UI in isolation. This allows rapid iteration on visual design and
  user interactions without I/O overhead.

  Usage:
      pipelines = ExGoCD.MockData.pipelines()
      grouped = ExGoCD.MockData.pipelines_by_group()
  """

  @doc """
  Returns a list of mock pipeline configurations with realistic data.
  """
  def pipelines do
    [
      %{
        name: "demo",
        group: "default",
        counter: 1,
        status: "Passed",
        triggered_by: "Triggered from dashboard",
        last_run: ~U[2026-06-22 11:00:00Z],
        stages: [
          %{name: "build", status: "Passed", duration: 15}
        ],
        materials: [
          %{type: "git", url: "https://github.com/d-led/ex_gocd.git", branch: "main"}
        ]
      },
      %{
        name: "build-linux",
        group: "Build",
        counter: 145,
        status: "Passed",
        triggered_by: "Triggered by dmitry",
        last_run: ~U[2026-02-05 10:30:00Z],
        stages: [
          %{name: "compile", status: "Passed", duration: 120},
          %{name: "test", status: "Passed", duration: 180},
          %{name: "package", status: "Passed", duration: 45}
        ],
        materials: [
          %{type: "git", url: "https://github.com/gocd/gocd.git", branch: "master"}
        ]
      },
      %{
        name: "build-windows",
        group: "Build",
        counter: 142,
        status: "Building",
        triggered_by: "Triggered by changes",
        last_run: ~U[2026-02-05 10:35:00Z],
        stages: [
          %{name: "compile", status: "Passed", duration: 150},
          %{name: "test", status: "Building", duration: nil},
          %{name: "package", status: "NotRun", duration: nil}
        ],
        materials: [
          %{type: "git", url: "https://github.com/gocd/gocd.git", branch: "master"}
        ]
      },
      %{
        name: "build-macos",
        group: "Build",
        counter: 138,
        status: "Failed",
        triggered_by: "Triggered by anonymous",
        last_run: ~U[2026-02-05 09:15:00Z],
        stages: [
          %{name: "compile", status: "Passed", duration: 130},
          %{name: "test", status: "Failed", duration: 95},
          %{name: "package", status: "Cancelled", duration: nil}
        ],
        materials: [
          %{type: "git", url: "https://github.com/gocd/gocd.git", branch: "master"}
        ]
      },
      %{
        name: "security-scan",
        group: "Quality",
        counter: 89,
        status: "Passed",
        triggered_by: "Triggered by gocd",
        last_run: ~U[2026-02-05 08:00:00Z],
        stages: [
          %{name: "dependency-check", status: "Passed", duration: 60},
          %{name: "sast", status: "Passed", duration: 240},
          %{name: "report", status: "Passed", duration: 15}
        ],
        materials: [
          %{type: "git", url: "https://github.com/gocd/gocd.git", branch: "master"}
        ]
      },
      %{
        name: "performance-tests",
        group: "Quality",
        counter: 23,
        status: "Passed",
        triggered_by: "Triggered by timer",
        last_run: ~U[2026-02-04 22:00:00Z],
        stages: [
          %{name: "setup", status: "Passed", duration: 30},
          %{name: "load-test", status: "Passed", duration: 600},
          %{name: "analysis", status: "Passed", duration: 120}
        ],
        materials: [
          %{type: "git", url: "https://github.com/gocd/gocd.git", branch: "master"}
        ]
      },
      %{
        name: "deploy-staging",
        group: "Deployment",
        counter: 234,
        status: "Passed",
        triggered_by: "Triggered by build-linux",
        last_run: ~U[2026-02-05 10:00:00Z],
        stages: [
          %{name: "deploy", status: "Passed", duration: 90},
          %{name: "smoke-tests", status: "Passed", duration: 45}
        ],
        materials: [
          %{type: "git", url: "https://github.com/gocd/gocd.git", branch: "master"}
        ]
      },
      %{
        name: "deploy-production",
        group: "Deployment",
        counter: 198,
        status: "Passed",
        triggered_by: "Triggered by deploy-staging",
        last_run: ~U[2026-02-04 16:30:00Z],
        stages: [
          %{name: "approval", status: "Passed", duration: 0},
          %{name: "deploy", status: "Passed", duration: 120},
          %{name: "smoke-tests", status: "Passed", duration: 60},
          %{name: "monitoring", status: "Passed", duration: 30}
        ],
        materials: [
          %{type: "git", url: "https://github.com/gocd/gocd.git", branch: "release"}
        ]
      },
      # ── Diamond fan-in/fan-out for VSM testing ─────────────────────────
      %{
        name: "upstream-lib",
        group: "demo",
        counter: 3,
        status: "Passed",
        triggered_by: "Triggered from dashboard",
        last_run: ~U[2026-06-22 11:20:00Z],
        stages: [
          %{name: "build", status: "Passed", duration: 45}
        ],
        materials: [
          %{type: "git", url: "https://github.com/d-led/ex_gocd.git", branch: "main"}
        ]
      },
      %{
        name: "component-a",
        group: "demo",
        counter: 3,
        status: "Passed",
        triggered_by: "Triggered by upstream-lib",
        last_run: ~U[2026-06-22 11:20:51Z],
        stages: [
          %{name: "build", status: "Passed", duration: 30}
        ],
        materials: [
          %{type: "dependency", url: "upstream-lib"}
        ]
      },
      %{
        name: "component-b",
        group: "demo",
        counter: 3,
        status: "Passed",
        triggered_by: "Triggered by upstream-lib",
        last_run: ~U[2026-06-22 11:20:51Z],
        stages: [
          %{name: "build", status: "Passed", duration: 30}
        ],
        materials: [
          %{type: "dependency", url: "upstream-lib"}
        ]
      },
      %{
        name: "integration-pipeline",
        group: "demo",
        counter: 4,
        status: "Passed",
        triggered_by: "Triggered by component-a + component-b",
        last_run: ~U[2026-06-22 11:21:00Z],
        stages: [
          %{name: "integrate", status: "Passed", duration: 60}
        ],
        materials: [
          %{type: "dependency", url: "component-a"},
          %{type: "dependency", url: "component-b"}
        ]
      },
      %{
        name: "downstream-app",
        group: "demo",
        counter: 3,
        status: "Passed",
        triggered_by: "Triggered by upstream-lib",
        last_run: ~U[2026-06-22 11:20:51Z],
        stages: [
          %{name: "package", status: "Passed", duration: 30}
        ],
        materials: [
          %{type: "dependency", url: "upstream-lib"}
        ]
      },
      %{
        name: "docs-build",
        group: "Documentation",
        counter: 67,
        status: "Passed",
        triggered_by: "Triggered by changes",
        last_run: ~U[2026-02-05 09:00:00Z],
        stages: [
          %{name: "build", status: "Passed", duration: 45},
          %{name: "deploy", status: "Passed", duration: 30}
        ],
        materials: [
          %{type: "git", url: "https://github.com/gocd/docs.git", branch: "master"}
        ]
      }
    ]
    |> Enum.map(fn p ->
      Map.merge(%{paused: false, paused_by: nil, pause_cause: nil, paused_at: nil}, p)
    end)
  end

  @doc """
  Returns pipelines grouped by their group name.
  """
  def pipelines_by_group do
    pipelines()
    |> Enum.group_by(& &1.group)
    |> Enum.sort_by(fn {group, _} -> group end)
  end

  @doc """
  Returns pipelines grouped by environment (mock environments).
  """
  def pipelines_by_environment do
    pipelines_with_env = [
      {"build-linux", "Development"},
      {"build-windows", "Development"},
      {"build-macos", "Development"},
      {"security-scan", "Development"},
      {"performance-tests", "Testing"},
      {"deploy-staging", "Staging"},
      {"deploy-production", "Production"},
      {"docs-build", "Development"}
    ]

    env_map = Map.new(pipelines_with_env)

    pipelines()
    |> Enum.group_by(fn pipeline ->
      Map.get(env_map, pipeline.name, "Default")
    end)
    |> Enum.sort_by(fn {env, _} -> env end)
  end

  @doc """
  Filters pipelines by search term (case-insensitive).
  """
  def filter_pipelines(pipelines, search_term) when is_binary(search_term) do
    search_lower = String.downcase(search_term)

    Enum.filter(pipelines, fn pipeline ->
      String.contains?(String.downcase(pipeline.name), search_lower)
    end)
  end

  @doc """
  Returns a single pipeline by name for detail views.
  """
  def get_pipeline(name) do
    Enum.find(pipelines(), &(&1.name == name))
  end

  @doc """
  Returns all mock SCM materials derived from mock pipeline configurations.
  """
  def get_all_mock_materials do
    pipelines()
    |> Enum.flat_map(fn p ->
      Enum.map(p.materials || [], fn mat ->
        Map.put(mat, :pipeline_name, p.name)
      end)
    end)
    |> Enum.group_by(fn mat -> {mat.type, mat.url, Map.get(mat, :branch) || ""} end)
    |> Enum.map(fn {{type, url, branch}, mats} ->
      pipelines = Enum.map(mats, & &1.pipeline_name) |> Enum.uniq() |> Enum.sort()

      %{
        type: type,
        url: url,
        branch: branch,
        pipelines: pipelines
      }
    end)
  end

  @doc """
  Mock config repositories for the admin config repos page.
  """
  def config_repos do
    [
      %{
        id: 1,
        url: "https://github.com/d-led/ex_gocd.git",
        branch: "main",
        source_type: "gocd_pipeline",
        material_type: "git",
        plugin_id: "",
        configuration: %{},
        last_parsed_at: ~U[2026-06-22 00:00:00Z],
        inserted_at: ~U[2026-06-20 00:00:00Z],
        updated_at: ~U[2026-06-22 00:00:00Z]
      },
      %{
        id: 2,
        url: "https://github.com/myteam/backend.git",
        branch: "main",
        source_type: "github_actions",
        material_type: "git",
        plugin_id: "",
        configuration: %{},
        last_parsed_at: nil,
        inserted_at: ~U[2026-06-21 00:00:00Z],
        updated_at: ~U[2026-06-21 00:00:00Z]
      }
    ]
  end

  @doc """
  Mock audit log entries for the audit log page.
  """
  def audit_log_entries do
    [
      %{
        actor: "admin",
        action: "pipeline_trigger",
        resource_type: "pipeline",
        resource_name: "build-linux",
        details: %{counter: 145},
        inserted_at: ~U[2026-06-22 07:00:00Z]
      },
      %{
        actor: "admin",
        action: "config_update",
        resource_type: "pipeline",
        resource_name: "deploy-staging",
        details: %{field: "environment_variables"},
        inserted_at: ~U[2026-06-22 06:30:00Z]
      },
      %{
        actor: "dmitry",
        action: "stage_approve",
        resource_type: "stage",
        resource_name: "build-linux/test",
        details: %{stage_counter: 1},
        inserted_at: ~U[2026-06-22 06:00:00Z]
      },
      %{
        actor: "admin",
        action: "pipeline_pause",
        resource_type: "pipeline",
        resource_name: "security-scan",
        details: %{cause: "maintenance window"},
        inserted_at: ~U[2026-06-22 05:00:00Z]
      },
      %{
        actor: "admin",
        action: "pipeline_unpause",
        resource_type: "pipeline",
        resource_name: "security-scan",
        details: %{},
        inserted_at: ~U[2026-06-22 04:00:00Z]
      },
      %{
        actor: "gocd",
        action: "pipeline_trigger",
        resource_type: "pipeline",
        resource_name: "performance-tests",
        details: %{counter: 23, trigger: "timer"},
        inserted_at: ~U[2026-06-21 22:00:00Z]
      }
    ]
  end
end
