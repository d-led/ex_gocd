defmodule ExGoCD.Mcp.Tools.Jobs do
  @moduledoc """
  Jobs: one job instance, its console, its history, and scheduling one by hand.

  A job instance is what the pipeline *asked for*; a job run is what an agent
  *did*, and it is where the console lives. Both are answered together because
  "the job failed" is answered by one and "why" by the other.

  `gocd_schedule_job` is the odd one: it queues work that belongs to no pipeline
  — the API endpoint for running a single job on the next idle agent. Most
  callers want `gocd_trigger_pipeline` instead.
  """

  alias ExGoCD.{AgentJobRuns, Pipelines, Scheduler}
  alias ExGoCD.Mcp.{Args, Auth, PipelineView, Render, Tool}

  @names ~w(gocd_job gocd_job_console gocd_job_history gocd_test_report gocd_schedule_job)

  @tools [
    %{
      "name" => "gocd_job",
      "title" => "One job instance",
      "description" =>
        "A job of a stage of a run: its state, its result, the agent that took it, and the " <>
          "build id its run was recorded under. Says whether there is a console to read, " <>
          "without reading it — `gocd_job_console` does that.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pipeline" => %{"type" => "string", "description" => "The pipeline's name."},
          "counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "The run's counter."
          },
          "stage" => %{"type" => "string", "description" => "The stage's name."},
          "stage_counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "The stage instance."
          },
          "job" => %{"type" => "string", "description" => "The job's name."}
        },
        "required" => ["pipeline", "counter", "stage", "stage_counter", "job"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_job_console",
      "title" => "A job's console output",
      "description" =>
        "The tail of the console log an agent wrote for a job. `lines` is how much to read " <>
          "(default 100): a long build's useful end is its last lines. A job no agent has " <>
          "picked up yet has no console, and is answered as such rather than as empty.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pipeline" => %{"type" => "string", "description" => "The pipeline's name."},
          "counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "The run's counter."
          },
          "stage" => %{"type" => "string", "description" => "The stage's name."},
          "stage_counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "The stage instance."
          },
          "job" => %{"type" => "string", "description" => "The job's name."},
          "lines" => %{"type" => "integer", "minimum" => 1, "maximum" => 2000, "default" => 100}
        },
        "required" => ["pipeline", "counter", "stage", "stage_counter", "job"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_job_history",
      "title" => "A job's history",
      "description" =>
        "The instances of one job across runs, newest first, with each one's state, result " <>
          "and when it was scheduled. Flakiness is visible here; one failure's cause is in " <>
          "`gocd_job_console`.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pipeline" => %{"type" => "string", "description" => "The pipeline's name."},
          "stage" => %{"type" => "string", "description" => "The stage's name."},
          "job" => %{"type" => "string", "description" => "The job's name."},
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100, "default" => 10},
          "offset" => %{"type" => "integer", "minimum" => 0, "default" => 0}
        },
        "required" => ["pipeline", "stage", "job"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_test_report",
      "title" => "The tests a job published",
      "description" =>
        "The test results a job wrote into its artifacts, read back: totals, and the cases " <>
          "that failed or errored with the first line of each message. `failed_only` is true " <>
          "by default, because the failed cases are the answer and the passing ones are the " <>
          "rest of the log. A job that published no report says so — which is not the same " <>
          "as a job whose tests all passed.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pipeline" => %{"type" => "string", "description" => "The pipeline's name."},
          "counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "The run's counter."
          },
          "stage" => %{"type" => "string", "description" => "The stage's name."},
          "stage_counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "The stage instance."
          },
          "job" => %{"type" => "string", "description" => "The job's name."},
          "failed_only" => %{
            "type" => "boolean",
            "default" => true,
            "description" => "Only the cases that failed or errored. False lists them all."
          },
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 500, "default" => 50}
        },
        "required" => ["pipeline", "counter", "stage", "stage_counter", "job"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_schedule_job",
      "title" => "Schedule a single job",
      "description" =>
        "Queues one job for the next matching idle agent, outside any pipeline — the " <>
          "`/api/jobs/schedule` endpoint. `resources` and `environments` say which agents " <>
          "may take it. For a pipeline run, which creates its stages and jobs together, use " <>
          "`gocd_trigger_pipeline`.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pipeline" => %{"type" => "string", "description" => "A label for the job's origin."},
          "stage" => %{"type" => "string", "description" => "A label for the job's stage."},
          "job" => %{"type" => "string", "description" => "A label for the job."},
          "resources" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Resource tags the agent must all have."
          },
          "environments" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Environments the agent must be in at least one of."
          }
        }
      },
      "annotations" => Tool.writes()
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
  def call("gocd_job", args, ctx), do: show(args, ctx)
  def call("gocd_job_console", args, ctx), do: console(args, ctx)
  def call("gocd_job_history", args, ctx), do: history(args, ctx)
  def call("gocd_test_report", args, ctx), do: test_report(args, ctx)
  def call("gocd_schedule_job", args, ctx), do: schedule(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  defp show(args, _ctx) do
    with {:ok, {job_instance, run}} <- find(args) do
      job = PipelineView.job(job_instance)

      structured = %{"job" => job, "run" => run_map(run)}

      text =
        [
          "#{job["name"]} · #{job["state"]}/#{job["result"]}",
          "Agent: #{job["agent_uuid"]}" <>
            if(structured["run"], do: " · build #{structured["run"]["build_id"]}", else: ""),
          "Scheduled: #{job["scheduled_at"]} · assigned: #{job["assigned_at"]} · completed: #{job["completed_at"]}",
          console_line(structured["run"])
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      Tool.ok(text, structured)
    end
  end

  defp console(args, _ctx) do
    with {:ok, {job_instance, run}} <- find(args),
         {:ok, lines} <- Args.integer(args, "lines", default: 100, min: 1, max: 2000) do
      case run do
        nil ->
          {:error,
           "No run is recorded for '#{job_instance.name}': no agent has picked it up yet, " <>
             "so there is no console to read."}

        run ->
          log = run.console_log || ""

          text =
            "#{job_instance.name} · #{run.state}/#{run.result || "Unknown"} · build #{run.build_id}\n" <>
              "#{line_count(log)} console line(s), last #{lines} shown\n\n" <>
              Render.tail(log, lines)

          Tool.ok(text, %{
            "job" => job_instance.name,
            "build_id" => run.build_id,
            "agent_uuid" => run.agent_uuid,
            "state" => run.state,
            "result" => run.result,
            "lines" => line_count(log),
            "console" => Render.tail(log, lines)
          })
      end
    end
  end

  defp history(args, _ctx) do
    with {:ok, pipeline} <- Args.required(args, "pipeline"),
         {:ok, stage} <- Args.required(args, "stage"),
         {:ok, job} <- Args.required(args, "job"),
         {:ok, limit} <- Args.integer(args, "limit", default: 10, min: 1, max: 100),
         {:ok, offset} <- Args.integer(args, "offset", default: 0, min: 0, max: 100_000) do
      instances = Pipelines.list_job_instances(pipeline, stage, job, offset: offset, limit: limit)

      text =
        "#{pipeline} · #{stage} · #{job}: #{length(instances)} instance(s) from #{offset}\n\n" <>
          Render.table(
            ["RUN", "STAGE #", "STATE", "RESULT", "AGENT", "SCHEDULED"],
            Enum.map(instances, fn instance ->
              [
                instance.stage_instance.pipeline_instance.counter,
                instance.stage_instance.counter,
                instance.state || "Scheduled",
                instance.result || "Unknown",
                instance.agent_uuid,
                Render.timestamp(instance.scheduled_at || instance.inserted_at)
              ]
            end)
          )

      Tool.ok(text, %{
        "pipeline" => pipeline,
        "stage" => stage,
        "job" => job,
        "offset" => offset,
        "instances" => Enum.map(instances, &PipelineView.job/1)
      })
    else
      {:error, message} -> {:error, message}
    end
  end

  defp test_report(args, _ctx) do
    with {:ok, {job_instance, _run}} <- find(args),
         {:ok, failed_only} <- failures_only(args),
         {:ok, limit} <- Args.integer(args, "limit", default: 50, min: 1, max: 500) do
      case ExGoCD.TestReport.get_by_job_instance(job_instance.id) do
        nil ->
          {:error,
           "No test report is stored for '#{job_instance.name}': the job published none. " <>
             "That is not the same as a job whose tests passed."}

        report ->
          report_answer(job_instance, report, failed_only, limit)
      end
    end
  end

  defp report_answer(job_instance, report, failed_only, limit) do
    cases =
      report.suites
      |> Enum.flat_map(fn suite ->
        Enum.map(suite.cases, fn test_case ->
          %{
            "suite" => suite.name,
            "test" => test_case.name,
            "result" => test_case.result,
            "time" => test_case.time,
            "failure_type" => test_case.failure_type,
            "message" => first_line(test_case.message)
          }
        end)
      end)
      |> Enum.filter(&(not failed_only or &1["result"] != "passed"))
      |> Enum.take(limit)

    totals = %{
      "total" => report.total_tests,
      "passed" => report.passed,
      "failed" => report.failed,
      "errored" => report.errored,
      "skipped" => report.skipped,
      "time_seconds" => report.total_time
    }

    text =
      [
        "#{job_instance.name}: #{report.total_tests} test(s) — #{report.passed} passed · " <>
          "#{report.failed} failed · #{report.errored} errored · #{report.skipped} skipped · " <>
          "#{Float.round(report.total_time, 2)}s",
        if(cases == [],
          do: "No failing case in this report.",
          else:
            Render.table(
              ["SUITE", "TEST", "RESULT", "TIME", "MESSAGE"],
              Enum.map(cases, fn test_case ->
                [
                  test_case["suite"],
                  test_case["test"],
                  test_case["result"],
                  test_case["time"],
                  Render.truncate(Render.cell(test_case["message"]), 120)
                ]
              end)
            )
        )
      ]
      |> Enum.join("\n\n")

    Tool.ok(text, %{"job" => job_instance.name, "totals" => totals, "cases" => cases})
  end

  # `failed_only` is true unless the caller says otherwise, and `Args.boolean/2`
  # cannot tell "absent" from "false".
  defp failures_only(args) do
    if Map.has_key?(args, "failed_only"), do: Args.boolean(args, "failed_only"), else: {:ok, true}
  end

  # A failure message is a stack trace more often than a sentence; the first line
  # is the sentence.
  defp first_line(nil), do: nil
  defp first_line(message), do: message |> String.split("\n", parts: 2) |> hd()

  defp schedule(args, ctx) do
    with {:ok, pipeline} <- Args.optional(args, "pipeline"),
         {:ok, stage} <- Args.optional(args, "stage"),
         {:ok, job} <- Args.optional(args, "job"),
         {:ok, resources} <- Args.strings(args, "resources"),
         {:ok, environments} <- Args.strings(args, "environments"),
         :ok <- Auth.require_pipeline_access(ctx.user, "schedule a job") do
      spec = %{
        "pipeline" => pipeline,
        "stage" => stage,
        "job" => job,
        "resources" => resources,
        "environments" => environments
      }

      case Scheduler.schedule_job(spec) do
        {:ok, job_id} ->
          Tool.ok(
            "Job queued as `#{job_id}`. `gocd_queue` shows what the scheduler is holding and " <>
              "whether an agent matches its resources.",
            %{
              "job_id" => job_id,
              "resources" => resources,
              "environments" => environments
            }
          )

        {:error, reason} ->
          {:error, "Could not queue the job: #{inspect(reason)}"}
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  # ── reading ────────────────────────────────────────────────────────

  defp find(args) do
    with {:ok, pipeline} <- Args.required(args, "pipeline"),
         {:ok, counter} <- Args.required_integer(args, "counter"),
         {:ok, stage} <- Args.required(args, "stage"),
         {:ok, stage_counter} <- Args.required_integer(args, "stage_counter"),
         {:ok, job} <- Args.required(args, "job") do
      case Pipelines.get_job_instance(pipeline, counter, stage, stage_counter, job) do
        nil ->
          {:error,
           "Job '#{job}' of #{pipeline} ##{counter}, stage #{stage} ##{stage_counter} not found."}

        instance ->
          {:ok,
           {instance,
            AgentJobRuns.get_run_by_params(pipeline, counter, stage, stage_counter, job)}}
      end
    end
  end

  defp run_map(nil), do: nil

  defp run_map(run) do
    %{
      "build_id" => run.build_id,
      "agent_uuid" => run.agent_uuid,
      "state" => run.state,
      "result" => run.result,
      "console_lines" => line_count(run.console_log || "")
    }
  end

  defp console_line(nil), do: "No agent has picked this job up yet: there is no console."

  defp console_line(%{"console_lines" => 0}), do: "The console is empty."

  defp console_line(%{"console_lines" => lines}),
    do: "Console: #{lines} line(s) — `gocd_job_console` reads them."

  defp line_count(""), do: 0
  defp line_count(text), do: text |> String.split("\n", trim: true) |> length()
end
