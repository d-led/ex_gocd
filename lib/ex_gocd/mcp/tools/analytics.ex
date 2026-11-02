defmodule ExGoCD.Mcp.Tools.Analytics do
  @moduledoc """
  The numbers, as trends rather than snapshots: how often a pipeline passes, how
  long it takes and waits, how busy the agents are, and what one run's value
  stream map looked like.

  These are the analytics pages' own computations — `ExGoCD.Analytics` and
  `ExGoCD.Pipelines.ValueStreamMap` — asked through the same functions the pages
  and the analytics API call. An answer here and an answer there cannot differ,
  because they are one answer.
  """

  alias ExGoCD.Analytics
  alias ExGoCD.Mcp.{Args, Render, Tool}
  alias ExGoCD.Pipelines.ValueStreamMap

  @names ~w(gocd_pipeline_analytics gocd_agent_analytics gocd_value_stream_map)

  @tools [
    %{
      "name" => "gocd_pipeline_analytics",
      "title" => "How pipelines have been doing",
      "description" =>
        "With `pipeline`: that pipeline's runs in the period — how many, the pass rate, the " <>
          "mean time to recovery, the average build and wait times, and the recent runs. " <>
          "Without it: every pipeline's run count and latest status, plus the pipelines with " <>
          "the longest average wait. The answer to \"is this pipeline healthy\" and to " <>
          "\"where is the queue hurting us\".",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pipeline" => %{
            "type" => "string",
            "description" => "One pipeline's name. Omit for all."
          },
          "days" => %{"type" => "integer", "minimum" => 1, "maximum" => 365, "default" => 30}
        }
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_agent_analytics",
      "title" => "How busy the agents are",
      "description" =>
        "With `agent_uuid`: that agent's state transitions and its utilization ratio in the " <>
          "period (0..1 — the share of the window it spent building). Without it: every " <>
          "agent's job counts and successes, richest first, with hostnames resolved. The " <>
          "answer to \"do we have enough agents\".",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "agent_uuid" => %{
            "type" => "string",
            "description" => "One agent's uuid. Omit for all."
          },
          "days" => %{"type" => "integer", "minimum" => 1, "maximum" => 365, "default" => 7}
        }
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_value_stream_map",
      "title" => "A value stream map",
      "description" =>
        "The value stream map for one run of a pipeline (`pipeline` and `counter`), or for a " <>
          "material revision (`material_fingerprint` and `revision`) — which pipelines that " <>
          "commit reached, and the stages each went through. The map is returned as data; " <>
          "the text is a summary of it.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pipeline" => %{"type" => "string", "description" => "A pipeline's name."},
          "counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "Its run's counter."
          },
          "material_fingerprint" => %{
            "type" => "string",
            "description" => "A material's fingerprint."
          },
          "revision" => %{"type" => "string", "description" => "A revision of that material."}
        }
      },
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
  def call("gocd_pipeline_analytics", args, ctx), do: pipeline_analytics(args, ctx)
  def call("gocd_agent_analytics", args, ctx), do: agent_analytics(args, ctx)
  def call("gocd_value_stream_map", args, ctx), do: value_stream_map(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  defp pipeline_analytics(args, _ctx) do
    with {:ok, pipeline} <- Args.optional(args, "pipeline"),
         {:ok, days} <- Args.integer(args, "days", default: 30, min: 1, max: 365) do
      if pipeline do
        one_pipeline(pipeline, days)
      else
        every_pipeline(days)
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp one_pipeline(name, days) do
    analysis = Analytics.pipeline_analytics(name, days)

    text =
      "#{name}: #{analysis.run_count} run(s) in the last #{days} day(s)\n" <>
        Render.kv([
          {"pass rate", percentage(analysis.pass_rate)},
          {"mean time to recovery", Render.duration(analysis.mttr_sec)},
          {"average build time", Render.duration(analysis.avg_build_time_sec)},
          {"average wait time", Render.duration(analysis.avg_wait_time_sec)}
        ]) <>
        "\n\n" <>
        runs_table(analysis.recent_runs)

    Tool.ok(text, %{
      "pipeline" => name,
      "days" => days,
      "run_count" => analysis.run_count,
      "pass_rate" => analysis.pass_rate,
      "mttr_sec" => analysis.mttr_sec,
      "avg_build_time_sec" => analysis.avg_build_time_sec,
      "avg_wait_time_sec" => analysis.avg_wait_time_sec,
      "recent_runs" => Enum.map(analysis.recent_runs, &run_map/1)
    })
  end

  defp every_pipeline(days) do
    pipelines = Analytics.all_pipelines_analytics(days)
    slowest = Analytics.top_pipelines_by_wait_time(days, 10)

    text =
      "#{length(pipelines)} pipeline(s) in the last #{days} day(s)\n\n" <>
        Render.table(
          ["PIPELINE", "RUNS", "LATEST"],
          Enum.map(pipelines, fn pipeline ->
            [pipeline.name, pipeline.run_count, pipeline.latest_status]
          end)
        ) <>
        "\n\nLongest average wait:\n" <>
        Render.table(
          ["PIPELINE", "AVERAGE WAIT"],
          Enum.map(slowest, fn pipeline ->
            [pipeline.name, Render.duration(pipeline.avg_wait_sec)]
          end)
        )

    Tool.ok(text, %{
      "days" => days,
      "pipelines" =>
        Enum.map(pipelines, fn pipeline ->
          %{
            "name" => pipeline.name,
            "run_count" => pipeline.run_count,
            "latest_status" => pipeline.latest_status
          }
        end),
      "longest_wait" =>
        Enum.map(slowest, fn pipeline ->
          %{"name" => pipeline.name, "avg_wait_sec" => pipeline.avg_wait_sec}
        end)
    })
  end

  defp agent_analytics(args, _ctx) do
    with {:ok, agent_uuid} <- Args.optional(args, "agent_uuid"),
         {:ok, days} <- Args.integer(args, "days", default: 7, min: 1, max: 365) do
      if agent_uuid do
        one_agent(agent_uuid, days)
      else
        every_agent(days)
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp one_agent(uuid, days) do
    now = DateTime.utc_now()
    from = DateTime.add(now, -days * 86_400, :second)
    transitions = Analytics.agent_transitions(uuid, from, now)
    utilization = Analytics.agent_utilization(uuid, from, now)

    text =
      "#{uuid}: utilization #{format_ratio(utilization)} over the last #{days} day(s), " <>
        "#{length(transitions)} state transition(s)\n\n" <>
        Render.table(
          ["WHEN", "FROM", "TO"],
          Enum.map(transitions, fn transition ->
            [
              Render.timestamp(transition.transitioned_at),
              transition.from_state,
              transition.to_state
            ]
          end)
        )

    Tool.ok(text, %{
      "agent_uuid" => uuid,
      "days" => days,
      "utilization" => utilization,
      "transitions" =>
        Enum.map(transitions, fn transition ->
          %{
            "from_state" => transition.from_state,
            "to_state" => transition.to_state,
            "transitioned_at" => Render.timestamp(transition.transitioned_at)
          }
        end)
    })
  end

  defp every_agent(days) do
    stats = Analytics.enriched_agent_analytics(days)

    text =
      "#{length(stats)} agent(s) in the last #{days} day(s)\n\n" <>
        Render.table(
          ["AGENT", "TYPE", "JOBS", "COMPLETED", "FAILED", "CANCELLED"],
          Enum.map(stats, fn stat ->
            [
              stat.hostname,
              stat.agent_type,
              stat.total_jobs,
              stat.completed,
              stat.failed,
              stat.cancelled
            ]
          end)
        )

    Tool.ok(text, %{
      "days" => days,
      "agents" =>
        Enum.map(stats, fn stat ->
          %{
            "agent_uuid" => stat.agent_uuid,
            "hostname" => stat.hostname,
            "agent_type" => stat.agent_type,
            "total_jobs" => stat.total_jobs,
            "completed" => stat.completed,
            "failed" => stat.failed,
            "cancelled" => stat.cancelled
          }
        end)
    })
  end

  defp value_stream_map(args, _ctx) do
    with {:ok, pipeline} <- Args.optional(args, "pipeline"),
         {:ok, fingerprint} <- Args.optional(args, "material_fingerprint"),
         {:ok, revision} <- Args.optional(args, "revision") do
      cond do
        pipeline ->
          pipeline_stream(pipeline, args)

        fingerprint && revision ->
          material_stream(fingerprint, revision)

        true ->
          {:error,
           "Say which map you want: `pipeline` and `counter`, or `material_fingerprint` and `revision`."}
      end
    end
  end

  defp pipeline_stream(pipeline, args) do
    with {:ok, counter} <- Args.required_integer(args, "counter") do
      case ValueStreamMap.get_pipeline_vsm(pipeline, counter) do
        {:ok, vsm} -> stream_answer("Value stream map of #{pipeline} ##{counter}", vsm)
        {:error, _reason} -> {:error, "#{pipeline} ##{counter} not found."}
      end
    end
  end

  defp material_stream(fingerprint, revision) do
    case ValueStreamMap.get_material_vsm(fingerprint, revision) do
      {:ok, vsm} ->
        stream_answer("Value stream map of material #{fingerprint} at #{revision}", vsm)

      {:error, _reason} ->
        {:error, "Material '#{fingerprint}' at '#{revision}' not found."}
    end
  end

  defp stream_answer(subject, vsm) do
    Tool.ok(
      "#{subject}\n\n" <> Render.truncate(inspect(vsm, pretty: true, limit: :infinity), 6_000),
      %{"subject" => subject, "value_stream_map" => vsm}
    )
  end

  # ── rendering ──────────────────────────────────────────────────────

  defp runs_table(runs) do
    Render.table(
      ["RUN", "LABEL", "STATUS", "BUILD TIME", "TRIGGERED"],
      Enum.map(runs, fn run ->
        [
          run.counter,
          run.label,
          run.status,
          Render.duration(run.build_time_sec),
          Render.timestamp(run.triggered_at)
        ]
      end)
    )
  end

  defp run_map(run) do
    %{
      "counter" => run.counter,
      "label" => run.label,
      "status" => run.status,
      "build_time_sec" => run.build_time_sec,
      "triggered_at" => Render.timestamp(run.triggered_at)
    }
  end

  defp percentage(nil), do: "—"
  defp percentage(value), do: "#{value}%"

  defp format_ratio(value) when is_float(value), do: "#{Float.round(value * 100, 1)}%"
  defp format_ratio(value), do: "#{value}"
end
