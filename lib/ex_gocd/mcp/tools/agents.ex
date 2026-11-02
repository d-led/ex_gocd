defmodule ExGoCD.Mcp.Tools.Agents do
  @moduledoc """
  Agents: what is connected, what it is doing, what it can run, and — for an
  administrator — the three changes a person makes from the agents page.

  The list answers "do I have capacity", which is the question behind most
  others ("why is my pipeline not running"). `gocd_agent` answers "what is wrong
  with this one" with the health it last reported and the jobs it most recently
  ran.
  """

  alias ExGoCD.{AgentHealths, AgentJobRuns, Agents, AuditLog.Events}
  alias ExGoCD.Mcp.{Args, Auth, Changeset, Render, Tool}

  @names ~w(gocd_list_agents gocd_agent gocd_update_agent gocd_kill_agent_tasks)

  @tools [
    %{
      "name" => "gocd_list_agents",
      "title" => "List agents and their capacity",
      "description" =>
        "Every agent this server knows, with its state (Idle, Building, LostContact, Missing), " <>
          "whether it is disabled, and the resources and environments it offers. Filter by " <>
          "`status` (`Idle`, `Building`, `LostContact`, `Missing`, `disabled`, `enabled`), by " <>
          "a required `resource`, or by words in the hostname. The counts say how much " <>
          "capacity is free right now.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "status" => %{"type" => "string", "description" => "A state, or `enabled`/`disabled`."},
          "resource" => %{
            "type" => "string",
            "description" => "Agents must have this resource tag."
          },
          "query" => %{
            "type" => "string",
            "description" => "Words the hostname or uuid must contain."
          },
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 200, "default" => 50}
        }
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_agent",
      "title" => "One agent in detail",
      "description" =>
        "One agent: its configuration, the last health it reported (CPU, memory, disk, " <>
          "uptime), and the jobs it ran most recently. This is the page to read when an " <>
          "agent is in LostContact or keeps failing builds.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "uuid" => %{
            "type" => "string",
            "description" => "The agent's uuid, from `gocd_list_agents`."
          },
          "runs" => %{"type" => "integer", "minimum" => 1, "maximum" => 50, "default" => 10}
        },
        "required" => ["uuid"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_update_agent",
      "title" => "Enable, disable or re-tag an agent",
      "description" =>
        "Changes an agent's configuration: `state` (`enabled` or `disabled`), `resources` and " <>
          "`environments` — each replaces the list it names, and omitting one leaves it alone. " <>
          "Disabling an agent takes it out of scheduling without losing it. An administrator's " <>
          "act, as in the agents page.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "uuid" => %{"type" => "string", "description" => "The agent's uuid."},
          "state" => %{"type" => "string", "enum" => ["enabled", "disabled"]},
          "resources" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "The agent's new resource tags, in full."
          },
          "environments" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "The environments the agent belongs to, in full."
          }
        },
        "required" => ["uuid"]
      },
      "annotations" => Tool.writes()
    },
    %{
      "name" => "gocd_kill_agent_tasks",
      "title" => "Cancel the work an agent is running",
      "description" =>
        "Cancels the job runs an agent is currently working on, as the agents page's kill " <>
          "button does — the last resort for a stuck build. Answers what would be cancelled " <>
          "unless `confirm` is true. An administrator's act.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "uuid" => %{"type" => "string", "description" => "The agent's uuid."},
          "confirm" => %{
            "type" => "boolean",
            "default" => false,
            "description" => "True cancels; false only reports what would be cancelled."
          }
        },
        "required" => ["uuid"]
      },
      "annotations" => Tool.destructive()
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
  def call("gocd_list_agents", args, ctx), do: list(args, ctx)
  def call("gocd_agent", args, ctx), do: show(args, ctx)
  def call("gocd_update_agent", args, ctx), do: update(args, ctx)
  def call("gocd_kill_agent_tasks", args, ctx), do: kill_tasks(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  defp list(args, _ctx) do
    with {:ok, status} <- Args.optional(args, "status"),
         {:ok, resource} <- Args.optional(args, "resource"),
         {:ok, query} <- Args.optional(args, "query"),
         {:ok, limit} <- Args.integer(args, "limit", default: 50, min: 1, max: 200) do
      all = Agents.list_agents()

      matching =
        all
        |> Enum.filter(&matches?(&1, status, resource, query))
        |> Enum.sort_by(&(&1.hostname || &1.uuid))

      shown = Enum.take(matching, limit)
      by_state = Enum.frequencies_by(all, &(&1.state || "Unknown"))
      idle = Enum.count(all, &(&1.state == "Idle" and not &1.disabled))

      text =
        "#{length(matching)} of #{length(all)} agent(s) · " <>
          (by_state
           |> Enum.sort()
           |> Enum.map_join(" · ", fn {state, count} -> "#{state} #{count}" end)) <>
          " · #{idle} idle and enabled\n\n" <>
          Render.table(
            ["UUID", "HOSTNAME", "STATE", "RESOURCES", "ENVIRONMENTS", "DISABLED"],
            Enum.map(shown, fn agent ->
              [
                agent.uuid,
                agent.hostname,
                agent.state,
                agent.resources,
                agent.environments,
                agent.disabled
              ]
            end)
          )

      Tool.ok(text, %{
        "total" => length(all),
        "matched" => length(matching),
        "by_state" => by_state,
        "idle_enabled" => idle,
        "agents" => Enum.map(shown, &agent_map/1)
      })
    else
      {:error, message} -> {:error, message}
    end
  end

  defp show(args, _ctx) do
    with {:ok, uuid} <- Args.required(args, "uuid"),
         {:ok, runs} <- Args.integer(args, "runs", default: 10, min: 1, max: 50) do
      case Agents.get_agent_by_uuid(uuid) do
        nil ->
          {:error, "Agent '#{uuid}' not found."}

        agent ->
          health = AgentHealths.latest_for_agent(uuid)

          recent_runs =
            AgentJobRuns.list_runs_for_agent(uuid)
            |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
            |> Enum.take(runs)

          structured = %{
            "agent" => agent_map(agent),
            "health" => health_map(health),
            "runs" => Enum.map(recent_runs, &run_map/1)
          }

          text =
            [
              "#{agent.hostname || agent.uuid} · #{agent.state}#{if agent.disabled, do: " · disabled", else: ""}",
              Render.kv([
                {"uuid", agent.uuid},
                {"ip", agent.ipaddress},
                {"resources", agent.resources},
                {"environments", agent.environments},
                {"elastic agent id", agent.elastic_agent_id},
                {"operating system", agent.operating_system},
                {"free space", free_space(agent.free_space)},
                {"last updated", Render.timestamp(agent.updated_at)}
              ]),
              health_text(structured["health"]),
              runs_text(recent_runs)
            ]
            |> Enum.reject(&(&1 in [nil, ""]))
            |> Enum.join("\n\n")

          Tool.ok(text, structured)
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp update(args, ctx) do
    with {:ok, uuid} <- Args.required(args, "uuid"),
         :ok <- Auth.require_admin(ctx.user, "change an agent's configuration"),
         {:ok, state} <- Args.optional(args, "state"),
         {:ok, resources} <- Args.optional_strings(args, "resources"),
         {:ok, environments} <- Args.optional_strings(args, "environments") do
      case Agents.get_agent_by_uuid(uuid) do
        nil ->
          {:error, "Agent '#{uuid}' not found."}

        agent ->
          change_agent(agent, state, resources, environments, ctx)
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp change_agent(agent, state, resources, environments, ctx) do
    if state == nil and resources == nil and environments == nil do
      {:error, "Nothing to change: give `state`, `resources` or `environments`."}
    else
      with {:ok, new_state} <- validate_state(state),
           {:ok, agent} <- apply_state(agent, new_state),
           {:ok, agent} <- apply_fields(agent, resources, environments) do
        audit_state(ctx.user.username, agent, new_state)
        Tool.ok(agent_change_text(agent, new_state), %{"agent" => agent_map(agent)})
      end
    end
  end

  defp validate_state(nil), do: {:ok, nil}
  defp validate_state("enabled"), do: {:ok, :enabled}
  defp validate_state("disabled"), do: {:ok, :disabled}

  defp validate_state(other),
    do: {:error, "`state` must be `enabled` or `disabled`, not #{inspect(other)}."}

  defp apply_state(agent, nil), do: {:ok, agent}

  defp apply_state(agent, :enabled) do
    case Agents.enable_agent(agent) do
      {:ok, agent} -> {:ok, agent}
      {:error, changeset} -> {:error, Changeset.message(changeset)}
    end
  end

  defp apply_state(agent, :disabled) do
    case Agents.disable_agent(agent) do
      {:ok, agent} -> {:ok, agent}
      {:error, changeset} -> {:error, Changeset.message(changeset)}
    end
  end

  defp apply_fields(agent, nil, nil), do: {:ok, agent}

  defp apply_fields(agent, resources, environments) do
    attrs =
      %{}
      |> maybe_put(:resources, resources)
      |> maybe_put(:environments, environments)

    case Agents.update_agent(agent, attrs) do
      {:ok, agent} -> {:ok, agent}
      {:error, changeset} -> {:error, Changeset.message(changeset)}
    end
  end

  defp audit_state(_actor, _agent, nil), do: :ok

  defp audit_state(actor, agent, :enabled), do: Events.agent_enabled(actor, agent.uuid)
  defp audit_state(actor, agent, :disabled), do: Events.agent_disabled(actor, agent.uuid)

  defp kill_tasks(args, ctx) do
    with {:ok, uuid} <- Args.required(args, "uuid"),
         {:ok, confirm} <- Args.boolean(args, "confirm"),
         :ok <- Auth.require_admin(ctx.user, "cancel an agent's running work") do
      case Agents.get_agent_by_uuid(uuid) do
        nil ->
          {:error, "Agent '#{uuid}' not found."}

        agent ->
          kill_agent_tasks(agent, confirm)
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp kill_agent_tasks(agent, false) do
    {:error,
     "Cancelling the running work of #{agent.hostname || agent.uuid} ends the job(s) it is " <>
       "building now; they will be recorded as cancelled. Call again with `confirm: true`."}
  end

  defp kill_agent_tasks(agent, true) do
    case Agents.kill_running_tasks(agent) do
      :ok ->
        Tool.ok(
          "Cancelled the running work of #{agent.hostname || agent.uuid}.",
          %{"uuid" => agent.uuid, "cancelled" => true}
        )

      {:error, :no_running_tasks} ->
        {:error, "#{agent.hostname || agent.uuid} has no running tasks to cancel."}
    end
  end

  # ── rendering ──────────────────────────────────────────────────────

  defp matches?(agent, status, resource, query) do
    status_matches?(agent, status) and resource_matches?(agent, resource) and
      text_matches?(agent.hostname || agent.uuid, query)
  end

  defp status_matches?(_agent, nil), do: true

  defp status_matches?(agent, status) do
    case String.downcase(status) do
      "enabled" -> not agent.disabled
      "disabled" -> agent.disabled
      state -> String.downcase(agent.state || "") == state
    end
  end

  defp resource_matches?(_agent, nil), do: true

  defp resource_matches?(agent, resource),
    do: String.downcase(resource) in Enum.map(agent.resources || [], &String.downcase/1)

  defp text_matches?(_value, nil), do: true

  defp text_matches?(value, query),
    do: String.contains?(String.downcase(to_string(value)), String.downcase(query))

  defp agent_map(agent) do
    %{
      "uuid" => agent.uuid,
      "hostname" => agent.hostname,
      "ipaddress" => agent.ipaddress,
      "state" => agent.state,
      "disabled" => agent.disabled,
      "resources" => agent.resources || [],
      "environments" => agent.environments || [],
      "elastic_agent_id" => agent.elastic_agent_id,
      "operating_system" => agent.operating_system,
      "free_space_mb" => agent.free_space,
      "updated_at" => Render.timestamp(agent.updated_at)
    }
  end

  defp health_map(nil), do: nil

  defp health_map(health) do
    %{
      "reported_at" => Render.timestamp(health.reported_at),
      "cpu_percent" => health.cpu_percent,
      "memory_mb" => health.memory_mb,
      "disk_free_mb" => health.disk_free_mb,
      "disk_total_mb" => health.disk_total_mb,
      "os" => health.os,
      "uptime_seconds" => health.uptime_seconds
    }
  end

  defp health_text(nil), do: "Health: this agent has never reported any."

  defp health_text(health) do
    "Health (reported #{health["reported_at"]}): CPU #{Render.cell(health["cpu_percent"])}% · " <>
      "memory #{Render.cell(health["memory_mb"])} MB · " <>
      "disk #{Render.cell(health["disk_free_mb"])} of #{Render.cell(health["disk_total_mb"])} MB free · " <>
      "up #{Render.duration(health["uptime_seconds"])} · #{Render.cell(health["os"])}"
  end

  defp runs_text([]), do: "No job runs recorded for this agent."

  defp runs_text(runs) do
    "Recent runs:\n" <>
      Render.table(
        ["WHEN", "PIPELINE", "STAGE", "JOB", "STATE", "RESULT"],
        Enum.map(runs, fn run ->
          [
            Render.timestamp(run.inserted_at),
            run.pipeline_name,
            run.stage_name,
            run.job_name,
            run.state,
            run.result
          ]
        end)
      )
  end

  defp run_map(run) do
    %{
      "build_id" => run.build_id,
      "pipeline_name" => run.pipeline_name,
      "pipeline_counter" => run.pipeline_counter,
      "stage_name" => run.stage_name,
      "stage_counter" => run.stage_counter,
      "job_name" => run.job_name,
      "state" => run.state,
      "result" => run.result,
      "inserted_at" => Render.timestamp(run.inserted_at)
    }
  end

  defp agent_change_text(agent, state) do
    change =
      case state do
        :enabled -> "enabled"
        :disabled -> "disabled"
        nil -> "updated"
      end

    "#{agent.hostname || agent.uuid} is #{change}: resources #{Render.cell(agent.resources)}, " <>
      "environments #{Render.cell(agent.environments)}."
  end

  defp free_space(nil), do: nil
  defp free_space(mb), do: "#{mb} MB"

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)
end
