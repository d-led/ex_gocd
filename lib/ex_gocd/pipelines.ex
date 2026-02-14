# Copyright 2026 ex_gocd
# Context for pipeline config and pipeline runs (instances).
# GoCD domain: PipelineConfig → Pipeline (instance) → Stage → Job → Task.

defmodule ExGoCD.Pipelines do
  @moduledoc """
  Pipeline configuration and pipeline run (instance) management.
  - List pipeline configs from DB (with stages, jobs, tasks).
  - Trigger a pipeline: create PipelineInstance, StageInstances, JobInstances; enqueue jobs to Scheduler.
  - Dashboard: list pipeline configs with latest instance status.
  """
  import Ecto.Query
  alias ExGoCD.Repo
  alias ExGoCD.Scheduler
  alias ExGoCD.Pipelines.{
    Pipeline,
    PipelineInstance,
    StageInstance,
    JobInstance
  }

  @doc """
  Lists all pipeline configs with stages and jobs (and tasks) preloaded.
  """
  def list_pipelines do
    Pipeline
    |> Repo.all()
    |> Repo.preload([stages: [jobs: :tasks]])
  end

  @doc """
  Gets a pipeline by name with stages and jobs preloaded. Returns nil if not found.
  """
  def get_pipeline_by_name(name) when is_binary(name) do
    Pipeline
    |> Repo.get_by(name: name)
    |> case do
      nil -> nil
      p -> Repo.preload(p, [stages: [jobs: :tasks]])
    end
  end

  @doc """
  Gets a pipeline by name. Raises if not found.
  """
  def get_pipeline_by_name!(name) when is_binary(name) do
    Pipeline
    |> Repo.get_by!(name: name)
    |> Repo.preload([stages: [jobs: :tasks]])
  end

  @doc """
  Returns the next counter for a pipeline (max counter + 1, or 1).
  """
  def next_counter(pipeline_id) when is_integer(pipeline_id) do
    from(pi in PipelineInstance,
      where: pi.pipeline_id == ^pipeline_id,
      select: max(pi.counter)
    )
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  @doc """
  Triggers a pipeline run: creates PipelineInstance, StageInstances, JobInstances for the first stage,
  and enqueues each job to the Scheduler. Jobs will be picked up by idle agents.
  Returns {:ok, pipeline_instance} or {:error, changeset}.
  """
  def trigger_pipeline(pipeline_name) when is_binary(pipeline_name) do
    pipeline = get_pipeline_by_name(pipeline_name)
    if is_nil(pipeline), do: {:error, :pipeline_not_found}, else: do_trigger_pipeline(pipeline)
  end

  defp do_trigger_pipeline(pipeline) do
    counter = next_counter(pipeline.id)
    now = DateTime.utc_now()
    label = String.replace(pipeline.label_template, "${COUNT}", to_string(counter))
    natural_order = counter * 1.0

    build_cause = %{
      "approver" => "anonymous",
      "triggerMessage" => "Triggered from dashboard",
      "triggerForced" => false,
      "materialRevisions" => []
    }

    Repo.transaction(fn ->
      instance =
        %PipelineInstance{}
        |> PipelineInstance.changeset(%{
          pipeline_id: pipeline.id,
          counter: counter,
          label: label,
          natural_order: natural_order,
          build_cause: build_cause
        })
        |> Repo.insert!()

      stages_ordered = Enum.sort_by(pipeline.stages, & &1.id)
      first_stage = List.first(stages_ordered)
      if is_nil(first_stage), do: raise("Pipeline has no stages")

      # Create stage instance for first stage (Building); others we skip for single-stage trigger
      stage_instance =
        %StageInstance{}
        |> StageInstance.changeset(%{
          pipeline_instance_id: instance.id,
          name: first_stage.name,
          counter: 1,
          order_id: 1,
          state: "Building",
          result: "Unknown",
          approval_type: first_stage.approval_type,
          created_time: now,
          fetch_materials: first_stage.fetch_materials,
          clean_working_dir: first_stage.clean_working_directory
        })
        |> Repo.insert!()

      scheduled_at = DateTime.to_naive(now)
      job_instances =
        Enum.map(first_stage.jobs, fn job ->
          %JobInstance{}
          |> JobInstance.changeset(%{
            stage_instance_id: stage_instance.id,
            job_id: job.id,
            name: job.name,
            state: "Scheduled",
            result: "Unknown",
            scheduled_at: scheduled_at,
            run_on_all_agents: job.run_on_all_agents || false,
            run_multiple_instance: false,
            identifier: "#{pipeline.name}/#{counter}/#{first_stage.name}/1/#{job.name}/1"
          })
          |> Repo.insert!()
        end)

      # Enqueue each job to Scheduler with spec from job config and job_instance_id
      for ji <- job_instances do
        job_config = Enum.find(first_stage.jobs, &(&1.id == ji.job_id))
        if job_config do
          build_command = build_command_from_job(job_config)
          spec =
            %{
              "pipeline" => pipeline.name,
              "stage" => first_stage.name,
              "job" => job_config.name,
              "resources" => job_config.resources || [],
              "environments" => [],
              "build_command" => build_command,
              "job_instance_id" => ji.id
            }
          Scheduler.schedule_job(spec)
        end
      end

      instance
    end)
  end

  defp build_command_from_job(job) do
    first_task = List.first(job.tasks || [])
    if first_task && first_task.type == "exec" do
      %{
        "name" => first_task.type,
        "command" => first_task.command || "echo",
        "args" => first_task.arguments || []
      }
    else
      %{"name" => "default", "command" => "echo", "args" => ["no task configured"]}
    end
  end

  @doc """
  Lists pipeline configs with their latest instance for dashboard display.
  Returns a list of maps compatible with dashboard pipeline widget (name, group, counter, status, triggered_by, last_run, stages).
  """
  def list_for_dashboard do
    list_pipelines()
    |> Enum.map(fn pipeline ->
      latest = get_latest_instance(pipeline.id)
      pipeline_to_dashboard_map(pipeline, latest)
    end)
  end

  defp get_latest_instance(pipeline_id) do
    from(pi in PipelineInstance,
      where: pi.pipeline_id == ^pipeline_id,
      order_by: [desc: pi.counter],
      limit: 1,
      preload: [stage_instances: :job_instances]
    )
    |> Repo.one()
  end

  defp pipeline_to_dashboard_map(pipeline, nil) do
    %{
      name: pipeline.name,
      group: pipeline.group || "default",
      counter: 0,
      status: "Unknown",
      triggered_by: "—",
      last_run: nil,
      stages: Enum.map(pipeline.stages || [], fn s -> %{name: s.name, status: "NotRun", duration: nil} end)
    }
  end

  defp pipeline_to_dashboard_map(pipeline, instance) do
    stages =
      (instance.stage_instances || [])
      |> Enum.sort_by(& &1.order_id)
      |> Enum.map(fn si ->
        duration = stage_duration(si)
        %{name: si.name, status: stage_status(si), duration: duration}
      end)

    # If we have config stages but no instances yet (e.g. only first stage created), pad with NotRun
    config_stage_names = Enum.map(pipeline.stages || [], & &1.name)
    filled_stages =
      Enum.map(config_stage_names, fn sname ->
        found = Enum.find(stages, fn s -> s.name == sname end)
        found || %{name: sname, status: "NotRun", duration: nil}
      end)

    build_cause = instance.build_cause || %{}
    triggered_by = build_cause["triggerMessage"] || "Triggered manually"

    %{
      name: pipeline.name,
      group: pipeline.group || "default",
      counter: instance.counter,
      status: pipeline_instance_status(instance),
      triggered_by: triggered_by,
      last_run: instance.inserted_at,
      stages: filled_stages
    }
  end

  defp stage_status(%StageInstance{state: "Building"}), do: "Building"
  defp stage_status(%StageInstance{state: "Completed", result: "Passed"}), do: "Passed"
  defp stage_status(%StageInstance{state: "Completed", result: "Failed"}), do: "Failed"
  defp stage_status(%StageInstance{state: "Completed", result: "Cancelled"}), do: "Cancelled"
  defp stage_status(_), do: "NotRun"

  defp stage_duration(%StageInstance{completed_at: nil}), do: nil
  defp stage_duration(%StageInstance{completed_at: completed, created_time: created})
       when not is_nil(completed) and not is_nil(created) do
    completed_dt = to_utc_datetime(completed)
    created_dt = to_utc_datetime(created)
    if completed_dt && created_dt, do: DateTime.diff(completed_dt, created_dt, :second), else: nil
  end
  defp stage_duration(_), do: nil

  defp to_utc_datetime(%DateTime{} = dt), do: dt
  defp to_utc_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp to_utc_datetime(_), do: nil

  defp pipeline_instance_status(instance) do
    stages = instance.stage_instances || []
    cond do
      Enum.any?(stages, fn s -> s.state == "Building" end) -> "Building"
      Enum.any?(stages, fn s -> s.result == "Failed" or s.result == "Cancelled" end) -> "Failed"
      Enum.all?(stages, fn s -> s.state == "Completed" and s.result == "Passed" end) -> "Passed"
      true -> "Unknown"
    end
  end

  @doc """
  Assigns a job instance to an agent (called when Scheduler assigns work for a pipeline job).
  """
  def assign_job_instance(job_instance_id, agent_uuid) when is_integer(job_instance_id) do
    ji = Repo.get(JobInstance, job_instance_id)
    if ji do
      now = NaiveDateTime.utc_now()
      ji
      |> JobInstance.changeset(%{state: "Assigned", agent_uuid: agent_uuid, assigned_at: now})
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Marks a job instance as completed (state Completed, result, completed_at).
  If all jobs in the stage are completed, marks the stage instance completed.
  """
  def complete_job_instance(job_instance_id, result) when is_integer(job_instance_id) do
    ji = Repo.get(JobInstance, job_instance_id) |> Repo.preload(:stage_instance)
    if ji do
      do_complete_job_instance(ji, result)
      :ok
    else
      {:error, :not_found}
    end
  end

  defp do_complete_job_instance(ji, result) do
    now = NaiveDateTime.utc_now()
    ji
    |> JobInstance.changeset(%{state: "Completed", result: result, completed_at: now})
    |> Repo.update()

    # Check if all jobs in this stage are completed
    stage = ji.stage_instance
    from(j in JobInstance, where: j.stage_instance_id == ^stage.id)
    |> Repo.all()
    |> then(fn jobs ->
      if Enum.all?(jobs, &(&1.state == "Completed")) do
        stage_result = if Enum.any?(jobs, &(&1.result == "Failed" or &1.result == "Cancelled")), do: "Failed", else: "Passed"
        stage
        |> StageInstance.changeset(%{
          state: "Completed",
          result: stage_result,
          completed_at: now,
          last_transitioned_time: DateTime.utc_now()
        })
        |> Repo.update()
      end
    end)

    :ok
  end
end
