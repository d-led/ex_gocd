defmodule ExGoCD.Mcp.Tools.Stages do
  @moduledoc """
  One stage of one run: what it did, its history, and the three things a person
  can do to it — approve it when it waits for a human, cancel it, and re-run the
  jobs that failed.

  Approving is not gated behind `confirm`: it is the act of saying yes, and a
  stage that is not waiting is refused by the context anyway. Cancelling and
  re-running are: both end or discard work that already happened, and a caller
  that meant to read the stage should not lose it to a mistyped name.
  """

  alias ExGoCD.{AuditLog.Events, Pipelines}
  alias ExGoCD.Mcp.{Args, Auth, PipelineView, Render, Tool}

  @names ~w(gocd_stage gocd_stage_history gocd_approve_stage gocd_cancel_stage
            gocd_rerun_failed_jobs)

  @tools [
    %{
      "name" => "gocd_stage",
      "title" => "One stage of one run",
      "description" =>
        "A stage instance and its jobs: state, result, approval type, who approved or " <>
          "cancelled it, when it was scheduled and completed, and each job's state, result " <>
          "and agent. This is the stage page, as data.",
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
            "description" => "Which instance of the stage, as `gocd_pipeline_instance` reports."
          }
        },
        "required" => ["pipeline", "counter", "stage", "stage_counter"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_stage_history",
      "title" => "A stage's history",
      "description" =>
        "The instances of one stage across a pipeline's runs, newest first, with each one's " <>
          "run counter, state and result. This is how to see whether a stage has been " <>
          "flaky — for the individual runs, `gocd_pipeline_history`.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pipeline" => %{"type" => "string", "description" => "The pipeline's name."},
          "stage" => %{"type" => "string", "description" => "The stage's name."},
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100, "default" => 10},
          "offset" => %{"type" => "integer", "minimum" => 0, "default" => 0}
        },
        "required" => ["pipeline", "stage"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_approve_stage",
      "title" => "Approve a stage that waits for a human",
      "description" =>
        "Approves a manual stage, which lets the run continue. A stage that is not awaiting " <>
          "approval is refused — read it with `gocd_pipeline_instance` first if unsure.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pipeline" => %{"type" => "string", "description" => "The pipeline's name."},
          "counter" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "The run's counter."
          },
          "stage" => %{"type" => "string", "description" => "The stage's name."}
        },
        "required" => ["pipeline", "counter", "stage"]
      },
      "annotations" => Tool.writes()
    },
    %{
      "name" => "gocd_cancel_stage",
      "title" => "Cancel a stage",
      "description" =>
        "Cancels a stage of a run: its unfinished jobs are cancelled and the run stops " <>
          "there. Answers what would be cancelled unless `confirm` is true.",
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
          "confirm" => %{
            "type" => "boolean",
            "default" => false,
            "description" => "True cancels; false only reports what would be cancelled."
          }
        },
        "required" => ["pipeline", "counter", "stage"]
      },
      "annotations" => Tool.destructive()
    },
    %{
      "name" => "gocd_rerun_failed_jobs",
      "title" => "Re-run the failed jobs of a stage",
      "description" =>
        "Resets the failed and cancelled jobs of one stage instance to scheduled and queues " <>
          "them again. Jobs that passed are left as they are. Answers what would be re-run " <>
          "unless `confirm` is true.",
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
            "description" => "Which instance of the stage."
          },
          "confirm" => %{
            "type" => "boolean",
            "default" => false,
            "description" => "True re-runs; false only reports what would be re-run."
          }
        },
        "required" => ["pipeline", "counter", "stage", "stage_counter"]
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
  def call("gocd_stage", args, ctx), do: show(args, ctx)
  def call("gocd_stage_history", args, ctx), do: history(args, ctx)
  def call("gocd_approve_stage", args, ctx), do: approve(args, ctx)
  def call("gocd_cancel_stage", args, ctx), do: cancel(args, ctx)
  def call("gocd_rerun_failed_jobs", args, ctx), do: rerun_failed(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  defp show(args, _ctx) do
    with {:ok, pipeline} <- Args.required(args, "pipeline"),
         {:ok, counter} <- Args.required_integer(args, "counter"),
         {:ok, stage} <- Args.required(args, "stage"),
         {:ok, stage_counter} <- Args.required_integer(args, "stage_counter") do
      case Pipelines.get_stage_instance(pipeline, counter, stage, stage_counter) do
        nil -> {:error, stage_not_found(pipeline, counter, stage, stage_counter)}
        stage_instance -> show_stage(stage_instance)
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp show_stage(stage_instance) do
    stage = PipelineView.stage(stage_instance)
    header = "#{stage["name"]} ##{stage["counter"]} · #{stage["state"]}/#{stage["result"]}"

    text =
      [
        header,
        "Approval: #{stage["approval_type"]}" <>
          if(stage["approved_by"], do: " · approved by #{stage["approved_by"]}", else: "") <>
          if(stage["cancelled_by"], do: " · cancelled by #{stage["cancelled_by"]}", else: ""),
        "Scheduled: #{stage["scheduled_at"]} · completed: #{stage["completed_at"]}",
        if(stage["rerun_of_counter"],
          do: "Re-run of stage counter #{stage["rerun_of_counter"]}.",
          else: nil
        ),
        "",
        PipelineView.job_table(stage_instance)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    Tool.ok(text, stage)
  end

  defp history(args, _ctx) do
    case Args.all(args,
           pipeline: :string,
           stage: :string,
           limit: {:integer, default: 10, min: 1, max: 100},
           offset: {:integer, default: 0, min: 0, max: 100_000}
         ) do
      {:ok, request} -> history_answer(request)
      {:error, message} -> {:error, message}
    end
  end

  defp history_answer(request) do
    instances =
      Pipelines.list_stage_instances(request.pipeline, request.stage,
        offset: request.offset,
        limit: request.limit
      )

    Tool.ok(history_text(request, instances), history_payload(request, instances))
  end

  @history_columns ["RUN", "STAGE #", "STATE", "RESULT", "JOBS", "COMPLETED"]

  defp history_text(request, instances) do
    "#{request.pipeline} · stage #{request.stage}: #{length(instances)} instance(s) from #{request.offset}\n\n" <>
      Render.table(@history_columns, Enum.map(instances, &history_row/1))
  end

  defp history_row(instance) do
    [
      instance.pipeline_instance.counter,
      instance.counter,
      instance.state || "Unknown",
      instance.result || "Unknown",
      Enum.map_join(instance.job_instances || [], ", ", & &1.name),
      Render.timestamp(instance.completed_at)
    ]
  end

  defp history_payload(request, instances) do
    %{
      "pipeline" => request.pipeline,
      "stage" => request.stage,
      "offset" => request.offset,
      "instances" => Enum.map(instances, &PipelineView.stage/1)
    }
  end

  defp approve(args, ctx) do
    with {:ok, pipeline} <- Args.required(args, "pipeline"),
         {:ok, counter} <- Args.required_integer(args, "counter"),
         {:ok, stage} <- Args.required(args, "stage"),
         :ok <- Auth.require_pipeline_access(ctx.user, "approve a stage") do
      case Pipelines.approve_stage(pipeline, counter, stage) do
        {:ok, _stage_instance} ->
          Tool.ok(
            "#{pipeline} ##{counter}: stage #{stage} approved; the run continues.",
            %{"pipeline" => pipeline, "counter" => counter, "stage" => stage, "approved" => true}
          )

        {:error, :stage_not_awaiting_approval} ->
          {:error, "Stage '#{stage}' of #{pipeline} ##{counter} is not awaiting approval."}

        {:error, :stage_config_not_found} ->
          {:error, "Pipeline '#{pipeline}' has no stage named '#{stage}'."}

        {:error, reason} ->
          {:error, "Could not approve '#{stage}': #{inspect(reason)}"}
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp cancel(args, ctx) do
    with {:ok, pipeline} <- Args.required(args, "pipeline"),
         {:ok, counter} <- Args.required_integer(args, "counter"),
         {:ok, stage} <- Args.required(args, "stage"),
         {:ok, confirm} <- Args.boolean(args, "confirm"),
         :ok <- Auth.require_pipeline_access(ctx.user, "cancel a stage"),
         {:ok, stage_instance} <- find_stage_in_run(pipeline, counter, stage) do
      if confirm do
        cancel_confirmed(pipeline, counter, stage, ctx)
      else
        {:error,
         "Cancelling #{pipeline} ##{counter}: stage #{stage} (#{stage_instance.state || "Unknown"}/" <>
           "#{stage_instance.result || "Unknown"}) stops the run there and cancels its " <>
           "unfinished jobs. Call again with `confirm: true` to cancel it."}
      end
    else
      {:error, message} -> {:error, message}
    end
  end

  defp cancel_confirmed(pipeline, counter, stage, ctx) do
    case Pipelines.cancel_stage(pipeline, counter, stage,
           actor: ctx.user.username,
           remote_ip: ctx.remote_ip
         ) do
      {:ok, _stage_instance} ->
        Tool.ok(
          "#{pipeline} ##{counter}: stage #{stage} cancelled.",
          %{"pipeline" => pipeline, "counter" => counter, "stage" => stage, "cancelled" => true}
        )

      {:error, :not_found} ->
        {:error, "Stage '#{stage}' of #{pipeline} ##{counter} not found."}
    end
  end

  defp rerun_failed(args, ctx) do
    with {:ok, request} <-
           Args.all(args,
             pipeline: :string,
             counter: :integer,
             stage: :string,
             stage_counter: :integer,
             confirm: :boolean
           ),
         :ok <- Auth.require_pipeline_access(ctx.user, "re-run failed jobs") do
      if request.confirm, do: rerun_confirmed(request, ctx), else: rerun_explained(request)
    else
      {:error, message} -> {:error, message}
    end
  end

  # Re-running is destructive to the run's record, so the first call only says
  # what the second one will do.
  defp rerun_explained(request) do
    {:error,
     "Re-running the failed jobs of #{request.pipeline} ##{request.counter}, stage #{request.stage}" <>
       "##{request.stage_counter} resets them to scheduled and queues them again, keeping the " <>
       "jobs that passed. Call again with `confirm: true` to do it."}
  end

  defp rerun_confirmed(request, ctx) do
    %{pipeline: pipeline, counter: counter, stage: stage, stage_counter: stage_counter} = request

    case Pipelines.rerun_failed_jobs(pipeline, counter, stage, stage_counter) do
      {:ok, count} ->
        Events.stage_failed_jobs_rerun(
          ctx.user.username,
          pipeline,
          counter,
          stage,
          stage_counter,
          count
        )

        Tool.ok(
          "#{pipeline} ##{counter}: re-running #{count} failed job(s) of stage #{stage} " <>
            "##{stage_counter}.",
          %{
            "pipeline" => pipeline,
            "counter" => counter,
            "stage" => stage,
            "stage_counter" => stage_counter,
            "jobs" => count
          }
        )

      {:error, :stage_not_found} ->
        {:error, "Stage '#{stage}' ##{stage_counter} of #{pipeline} ##{counter} not found."}

      {:error, :no_failed_jobs} ->
        Tool.ok(
          "#{pipeline} ##{counter}: stage #{stage} ##{stage_counter} has no failed jobs to re-run.",
          %{"pipeline" => pipeline, "jobs" => 0}
        )

      {:error, reason} ->
        {:error, "Could not re-run the failed jobs of '#{stage}': #{reason}"}
    end
  end

  # ── finding a stage ────────────────────────────────────────────────

  # Approving and cancelling address a stage by name, not by its instance
  # counter — the context finds the instance — so a read has to pick the one in
  # the named run: only a stage can have more than one instance per run.
  defp find_stage_in_run(pipeline, counter, stage) do
    instance =
      pipeline
      |> Pipelines.list_stage_instances(stage, limit: 100)
      |> Enum.find(&(&1.pipeline_instance.counter == counter))

    case instance do
      nil -> {:error, stage_not_found(pipeline, counter, stage)}
      instance -> {:ok, instance}
    end
  end

  defp stage_not_found(pipeline, counter, stage),
    do: "Stage '#{stage}' of #{pipeline} ##{counter} not found."

  defp stage_not_found(pipeline, counter, stage, stage_counter),
    do: "Stage '#{stage}' ##{stage_counter} of #{pipeline} ##{counter} not found."
end
