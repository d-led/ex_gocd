defmodule ExGoCD.Mcp.Tools.Server do
  @moduledoc """
  The questions about the deployment itself, before any pipeline is named: what
  is here, what is the state of every pipeline at once, why is queued work not
  moving, and who did what.

  These four tools exist because an assistant with a shell would otherwise go
  looking for a database, a log file or a config on its own side of the
  connection — and the answers are here, computed by the same code the web pages
  use.
  """

  alias ExGoCD.{Agents, AuditLog, ConfigVersion, MaintenanceMode, Pipelines, Scheduler, Stats}
  alias ExGoCD.Mcp.{Args, Render, Tool}
  alias ExGoCDWeb.AgentPresence

  @names ~w(gocd_server_info gocd_dashboard gocd_queue gocd_audit_log gocd_server_stats)

  @tools [
    %{
      "name" => "gocd_server_info",
      "title" => "What this GoCD server is, as numbers",
      "description" =>
        "The state of this deployment in one answer: its version, how many pipelines it " <>
          "has, its agents counted by state (idle, building, disabled), how many jobs are " <>
          "waiting in the queue, how many configuration versions are recorded, whether " <>
          "maintenance mode is on, and whether disk space is a problem. Ask this before " <>
          "asking anything else about a server you have not seen.",
      "inputSchema" => %{"type" => "object", "properties" => %{}},
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_dashboard",
      "title" => "Every pipeline's latest status",
      "description" =>
        "The dashboard's own data: each pipeline with its group, its latest run's counter " <>
          "and status (Passed, Failed, Building, Cancelled, Unknown), and whether it is " <>
          "paused. Filter by `group` or by words in the name. This is the answer to " <>
          "\"what is the state of everything\" — for one pipeline's detail use " <>
          "`gocd_pipeline_status` or `gocd_pipeline_instance`.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "group" => %{"type" => "string", "description" => "Only this pipeline group."},
          "query" => %{
            "type" => "string",
            "description" => "Words the pipeline name must contain."
          },
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 200, "default" => 40}
        }
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_queue",
      "title" => "Why queued work is not moving",
      "description" =>
        "What the scheduler is holding: how many jobs are pending, which ones are in the " <>
          "in-memory queue and which are scheduled in the database, with their resources " <>
          "and how long they have waited. Give `resources` to ask the question the job " <>
          "page asks — which agents could run a job needing these tags, and for the ones " <>
          "that cannot, what they are missing.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "resources" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Resource tags a job needs, to diagnose why it is not picked up."
          },
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100, "default" => 20}
        }
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_audit_log",
      "title" => "Who did what",
      "description" =>
        "The audit log, newest first: pipeline triggers, pauses, cancellations and agent " <>
          "changes, with the actor and the reason. Every filter is optional and they " <>
          "combine; string filters match case-insensitively anywhere in the field. Use " <>
          "`date_from`/`date_to` (`YYYY-MM-DD`) to bound the period.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "actor" => %{"type" => "string", "description" => "Who acted, e.g. `admin`."},
          "action" => %{
            "type" => "string",
            "description" => "The event type, e.g. `pipeline.triggered`."
          },
          "resource_type" => %{"type" => "string", "description" => "e.g. `pipeline`, `agent`."},
          "resource_name" => %{"type" => "string", "description" => "e.g. a pipeline's name."},
          "date_from" => %{"type" => "string", "description" => "Earliest day, `YYYY-MM-DD`."},
          "date_to" => %{"type" => "string", "description" => "Latest day, `YYYY-MM-DD`."},
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 200, "default" => 25}
        }
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_server_stats",
      "title" => "This node's numbers",
      "description" =>
        "The payload `/api/stats` publishes: agents counted by state (idle, building, lost " <>
          "contact, disabled, pending), jobs pending and running, this node's uptime and " <>
          "memory, and how many agents are connected right now. Use it when the question is " <>
          "\"is this server working hard or idle\", which `gocd_server_info` does not answer.",
      "inputSchema" => %{"type" => "object", "properties" => %{}},
      "annotations" => Tool.read_only()
    }
  ]

  @doc "The definitions of this family's tools."
  @spec definitions() :: [map()]
  def definitions, do: @tools

  @doc "The names of this family's tools."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "Whether this family answers to a tool name."
  @spec handles?(String.t()) :: boolean()
  def handles?(name), do: name in @names

  @doc "Calls one of this family's tools."
  @spec call(String.t(), map(), Tool.ctx()) :: Tool.result() | :unknown_tool
  def call("gocd_server_info", args, ctx), do: about(args, ctx)
  def call("gocd_dashboard", args, ctx), do: dashboard(args, ctx)
  def call("gocd_queue", args, ctx), do: queue(args, ctx)
  def call("gocd_audit_log", args, ctx), do: audit_log(args, ctx)
  def call("gocd_server_stats", args, ctx), do: server_stats(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  defp about(_args, _ctx) do
    agents = Agents.list_agents()
    queue = Scheduler.get_queue_state()
    by_state = Enum.frequencies_by(agents, &(&1.state || "Unknown"))
    disabled = Enum.count(agents, & &1.disabled)
    maintenance = MaintenanceMode.info()
    disk = disk_status()

    structured = %{
      "version" => version(),
      "pipelines" => Pipelines.count_pipelines(),
      "agents" => %{
        "total" => length(agents),
        "by_state" => by_state,
        "disabled" => disabled
      },
      "queue" => %{"pending" => queue.pending_count},
      "config_versions" => ConfigVersion.count(),
      "maintenance_mode" => maintenance.enabled,
      "disk" => to_string(disk)
    }

    text =
      [
        "GoCD #{version()} · #{structured["pipelines"]} pipeline(s) · #{length(agents)} agent(s)",
        "",
        "Agents: " <> describe_agents(by_state, disabled),
        "Queue: #{queue.pending_count} job(s) pending",
        "Config: #{structured["config_versions"]} version(s) recorded",
        "Maintenance mode: #{if maintenance.enabled, do: "on", else: "off"}",
        "Disk space: #{disk}"
      ]
      |> Enum.join("\n")

    Tool.ok(text, structured)
  end

  defp dashboard(args, _ctx) do
    with {:ok, group} <- Args.optional(args, "group"),
         {:ok, query} <- Args.optional(args, "query"),
         {:ok, limit} <- Args.integer(args, "limit", default: 40, min: 1, max: 200) do
      all = Pipelines.list_for_dashboard()

      matching =
        Enum.filter(all, fn pipeline ->
          text_matches?(pipeline.group, group) and text_matches?(pipeline.name, query)
        end)

      shown = Enum.take(matching, limit)
      statuses = Enum.frequencies_by(matching, &(&1.status || "Unknown"))
      paused = Enum.count(matching, & &1.paused)

      text =
        "#{length(matching)} of #{length(all)} pipeline(s) · " <>
          (statuses
           |> Enum.sort()
           |> Enum.map_join(" · ", fn {status, count} -> "#{status} #{count}" end)) <>
          " · #{paused} paused\n\n" <>
          Render.table(
            ["PIPELINE", "GROUP", "RUN", "STATUS", "PAUSED"],
            Enum.map(shown, fn pipeline ->
              [
                pipeline.name,
                pipeline.group,
                counter(pipeline.counter),
                pipeline.status,
                pipeline.paused
              ]
            end)
          )

      structured = %{
        "total" => length(all),
        "matched" => length(matching),
        "by_status" => statuses,
        "paused" => paused,
        "pipelines" =>
          Enum.map(shown, fn pipeline ->
            %{
              "name" => pipeline.name,
              "group" => pipeline.group,
              "counter" => pipeline.counter,
              "status" => pipeline.status,
              "paused" => pipeline.paused,
              "paused_by" => pipeline.paused_by
            }
          end)
      }

      Tool.ok(text, structured)
    end
  end

  defp queue(args, _ctx) do
    with {:ok, resources} <- Args.strings(args, "resources"),
         {:ok, limit} <- Args.integer(args, "limit", default: 20, min: 1, max: 100) do
      state = Scheduler.get_queue_state()
      diagnosis = Scheduler.diagnose_pending_job(resources)
      shown = Enum.take(state.in_memory_jobs, limit)

      text =
        [
          "Queue: #{state.pending_count} pending — #{state.in_memory_count} in memory, " <>
            "#{state.db_count} scheduled in the database",
          "",
          if(shown == [],
            do: "The in-memory queue is empty.",
            else:
              Render.table(
                ["PIPELINE", "RUN", "STAGE", "JOB", "RESOURCES", "WAITING SINCE"],
                Enum.map(shown, fn job ->
                  [
                    job.pipeline,
                    counter(job.pipeline_counter),
                    job.stage,
                    job.job,
                    job.resources,
                    Render.timestamp(job.inserted_at)
                  ]
                end)
              )
          ),
          diagnosis(diagnosis)
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n")

      Tool.ok(text, %{
        "pending" => state.pending_count,
        "in_memory" => %{"count" => state.in_memory_count, "jobs" => shown},
        "scheduled_in_database" => state.db_count,
        "diagnosis" => diagnosis
      })
    end
  end

  defp audit_log(args, _ctx) do
    with {:ok, actor} <- Args.optional(args, "actor"),
         {:ok, action} <- Args.optional(args, "action"),
         {:ok, resource_type} <- Args.optional(args, "resource_type"),
         {:ok, resource_name} <- Args.optional(args, "resource_name"),
         {:ok, from} <- Args.date(args, "date_from"),
         {:ok, to} <- Args.date(args, "date_to"),
         {:ok, limit} <- Args.integer(args, "limit", default: 25, min: 1, max: 200) do
      entries =
        AuditLog.search(%{
          actor: actor,
          action: action,
          resource_type: resource_type,
          resource_name: resource_name,
          date_from: from,
          date_to: to
        })
        |> Enum.take(limit)

      text =
        if entries == [] do
          "No audit entries match."
        else
          "#{length(entries)} audit entr(y/ies), newest first\n\n" <>
            Render.table(
              ["WHEN", "ACTOR", "ACTION", "RESOURCE", "DETAILS"],
              Enum.map(entries, fn entry ->
                [
                  Render.timestamp(entry.inserted_at),
                  entry.actor,
                  entry.action,
                  resource(entry),
                  Render.truncate(inspect_details(entry.details), 60)
                ]
              end)
            )
        end

      structured = %{
        "entries" =>
          Enum.map(entries, fn entry ->
            %{
              "inserted_at" => Render.timestamp(entry.inserted_at),
              "actor" => entry.actor,
              "action" => entry.action,
              "resource_type" => entry.resource_type,
              "resource_name" => entry.resource_name,
              "details" => entry.details
            }
          end)
      }

      Tool.ok(text, structured)
    end
  end

  defp server_stats(_args, _ctx) do
    report = Stats.report(map_size(AgentPresence.list("agent")))

    text =
      [
        "Agents: #{report.agents.total} total · #{report.agents.idle} idle · " <>
          "#{report.agents.building} building · #{report.agents.lost_contact} lost contact · " <>
          "#{report.agents.disabled} disabled",
        "Jobs: #{report.jobs.pending} pending · #{report.jobs.running} running",
        "System: up #{Render.duration(report.system.uptime_seconds)} · " <>
          "#{megabytes(report.system.memory_total_bytes)} MB · " <>
          "#{report.system.active_connections} agent connection(s)"
      ]
      |> Enum.join("\n")

    Tool.ok(text, %{
      "agents" => stringify(report.agents),
      "jobs" => stringify(report.jobs),
      "system" => stringify(report.system)
    })
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp megabytes(bytes), do: Float.round(bytes / 1_048_576, 1)

  # ── rendering ──────────────────────────────────────────────────────

  defp describe_agents(by_state, disabled) do
    states =
      by_state
      |> Enum.sort()
      |> Enum.map_join(" · ", fn {state, count} -> "#{state} #{count}" end)

    if disabled > 0, do: "#{states} · #{disabled} disabled", else: states
  end

  defp diagnosis(nil), do: nil

  defp diagnosis(%{matching_agents: matching, non_matching_detail: detail} = result) do
    lines =
      ["#{length(matching)} agent(s) can run a job with these resources"] ++
        Enum.map(matching, &matching_line/1) ++
        Enum.map(detail, &missing_line/1) ++
        connection_note(result)

    Enum.join(lines, "\n")
  end

  defp matching_line(agent), do: "  ✓ #{agent.hostname || agent.uuid} (#{agent.uuid})"

  defp missing_line(agent) do
    "  ✗ #{agent.hostname || agent.uuid} has #{Render.cell(agent.has)}, " <>
      "missing #{Render.cell(agent.missing)}"
  end

  defp connection_note(%{any_agent_connected: true}), do: []
  defp connection_note(_result), do: ["", "  No agent is connected at all."]

  defp resource(entry) do
    case {entry.resource_type, entry.resource_name} do
      {nil, _} -> "—"
      {type, nil} -> type
      {type, name} -> "#{type} #{name}"
    end
  end

  # Audit details are a JSON object whose shape depends on the event type; the
  # map is the honest rendering, and the text is only a summary of it.
  defp inspect_details(details) when is_map(details) and map_size(details) > 0 do
    details
    |> Enum.sort()
    |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp inspect_details(_details), do: "—"

  defp text_matches?(_value, nil), do: true
  defp text_matches?(nil, _filter), do: false

  defp text_matches?(value, filter) do
    String.contains?(String.downcase(to_string(value)), String.downcase(filter))
  end

  defp counter(0), do: "—"
  defp counter(value), do: to_string(value)

  defp version do
    case Application.spec(:ex_gocd, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end

  # The disk monitor is a process of its own. A request that arrives while it is
  # restarting must still be answered, and "unknown" is the answer that does not
  # claim a healthy disk.
  defp disk_status do
    try do
      ExGoCD.Monitors.DiskSpace.status()
    rescue
      _ -> "unknown"
    catch
      :exit, _ -> "unknown"
    end
  end
end
