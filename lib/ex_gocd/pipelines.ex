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
  alias ExGoCD.Pipelines.{
    Job,
    JobInstance,
    Material,
    Pipeline,
    PipelineInstance,
    Stage,
    StageInstance,
    Task
  }
  alias ExGoCD.Repo
  alias ExGoCD.Scheduler

  @doc """
  Lists all pipeline configs with stages and jobs (and tasks) preloaded.
  """
  def list_pipelines do
    Pipeline
    |> Repo.all()
    |> Repo.preload([:materials, stages: [jobs: :tasks]])
  end

  @doc """
  Gets a pipeline by name with stages and jobs preloaded. Returns nil if not found.
  """
  def get_pipeline_by_name(name) when is_binary(name) do
    Pipeline
    |> Repo.get_by(name: name)
    |> case do
      nil -> nil
      p -> Repo.preload(p, [:materials, stages: [jobs: :tasks]])
    end
  end

  @doc """
  Gets a pipeline by name. Raises if not found.
  """
  def get_pipeline_by_name!(name) when is_binary(name) do
    Pipeline
    |> Repo.get_by!(name: name)
    |> Repo.preload([:materials, stages: [jobs: :tasks]])
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
    cond do
      is_nil(pipeline) -> {:error, :pipeline_not_found}
      pipeline.paused -> {:error, :pipeline_paused}
      true -> do_trigger_pipeline(pipeline)
    end
  end

  @doc """
  Pauses a pipeline, preventing scheduled or manual triggers.
  """
  def pause_pipeline(pipeline_name, paused_by \\ "anonymous", pause_cause \\ "") when is_binary(pipeline_name) do
    case get_pipeline_by_name(pipeline_name) do
      nil -> {:error, :pipeline_not_found}
      pipeline ->
        pipeline
        |> Pipeline.changeset(%{
          paused: true,
          paused_by: paused_by,
          pause_cause: pause_cause,
          paused_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
        |> case do
          {:ok, updated_pipeline} ->
            Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
            {:ok, updated_pipeline}
          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Unpauses a pipeline.
  """
  def unpause_pipeline(pipeline_name) when is_binary(pipeline_name) do
    case get_pipeline_by_name(pipeline_name) do
      nil -> {:error, :pipeline_not_found}
      pipeline ->
        pipeline
        |> Pipeline.changeset(%{
          paused: false,
          paused_by: nil,
          pause_cause: nil,
          paused_at: nil
        })
        |> Repo.update()
        |> case do
          {:ok, updated_pipeline} ->
            Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
            {:ok, updated_pipeline}
          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp resolve_material_revisions(pipeline) do
    Enum.map(pipeline.materials || [], fn material ->
      revision =
        if material.type == "git" and is_binary(material.url) and material.url != "" and System.find_executable("git") do
          branch = material.branch || "HEAD"
          case System.cmd("git", ["ls-remote", material.url, branch]) do
            {output, 0} ->
              case String.split(output) do
                [sha, _ref | _] -> sha
                _ -> "HEAD"
              end
            _ ->
              "HEAD"
          end
        else
          "HEAD"
        end

      %{
        "material" => %{
          "id" => material.id,
          "type" => material.type,
          "url" => material.url,
          "branch" => material.branch || "master",
          "destination" => material.destination || ""
        },
        "changed" => true,
        "modifications" => [
          %{
            "revision" => revision,
            "modifiedTime" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "comment" => "Triggered commit",
            "username" => "gocd"
          }
        ]
      }
    end)
  end

  defp do_trigger_pipeline(pipeline) do
    counter = next_counter(pipeline.id)
    now = DateTime.utc_now()
    label = String.replace(pipeline.label_template, "${COUNT}", to_string(counter))
    natural_order = counter * 1.0

    material_revisions = resolve_material_revisions(pipeline)

    build_cause = %{
      "approver" => "anonymous",
      "triggerMessage" => "Triggered from dashboard",
      "triggerForced" => false,
      "materialRevisions" => material_revisions
    }

    result =
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

        {instance, first_stage, job_instances}
      end)

    case result do
      {:ok, {instance, first_stage, job_instances}} ->
        for ji <- job_instances do
          job_config = Enum.find(first_stage.jobs, &(&1.id == ji.job_id))
          schedule_job_if_config(pipeline, counter, first_stage, job_config, ji)
        end
        Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
        {:ok, instance}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_job_if_config(_pipeline, _counter, _stage, nil, _ji), do: :noop

  defp schedule_job_if_config(pipeline, counter, stage, job_config, ji) do
    build_command = build_command_from_job(job_config)

    spec = %{
      "pipeline" => pipeline.name,
      "pipeline_counter" => counter,
      "stage" => stage.name,
      "stage_counter" => 1,
      "job" => job_config.name,
      "resources" => job_config.resources || [],
      "environments" => [],
      "build_command" => build_command,
      "job_instance_id" => ji.id
    }

    Scheduler.schedule_job(spec)
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
  Gets a pipeline instance by pipeline name and counter, with preloaded stage and job instances.
  """
  def get_pipeline_instance(pipeline_name, counter) when is_binary(pipeline_name) and is_integer(counter) do
    query =
      from pi in PipelineInstance,
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and pi.counter == ^counter,
        preload: [:pipeline, stage_instances: :job_instances]

    Repo.one(query)
  end

  @doc """
  Compares two pipeline instances and returns the SCM revisions and modifications.
  """
  def compare_instances(pipeline_name, from_counter, to_counter) do
    from_instance = if from_counter > 0, do: get_pipeline_instance(pipeline_name, from_counter), else: nil
    to_instance = get_pipeline_instance(pipeline_name, to_counter)

    # Extract materials from pipeline config, or from the instances if configs missing
    pipeline = get_pipeline_by_name(pipeline_name)
    materials = if pipeline, do: pipeline.materials, else: []

    # Map each material to its revisions in from_instance and to_instance
    Enum.map(materials, fn material ->
      from_rev_info = extract_revision_info(from_instance, material.id)
      to_rev_info = extract_revision_info(to_instance, material.id)

      # Accumulate modifications that happened in between (i.e. those in to_instance)
      modifications =
        case to_rev_info do
          %{modifications: mods} -> mods
          _ -> []
        end

      %{
        material_id: material.id,
        type: material.type,
        url: material.url,
        branch: material.branch || "master",
        from_revision: from_rev_info[:revision] || "Unknown",
        to_revision: to_rev_info[:revision] || "Unknown",
        modifications: modifications
      }
    end)
  end

  defp extract_revision_info(nil, _material_id), do: %{revision: "N/A", modifications: []}
  defp extract_revision_info(instance, material_id) do
    build_cause = instance.build_cause || %{}
    material_revisions = build_cause["materialRevisions"] || []

    found =
      Enum.find(material_revisions, fn rev ->
        mat_id = get_in(rev, ["material", "id"])
        # Handle string vs integer IDs gracefully
        to_string(mat_id) == to_string(material_id)
      end)

    if found do
      mods = found["modifications"] || []
      latest_mod = List.first(mods) || %{}
      %{
        revision: latest_mod["revision"] || "Unknown",
        modifications: mods
      }
    else
      %{revision: "N/A", modifications: []}
    end
  end

  @doc """
  Reruns a stage instance. Creates a new StageInstance with an incremented counter.
  Optional list of job_names to rerun only those, or atom :failed to rerun only failed/cancelled jobs.
  """
  def rerun_stage(pipeline_name, pipeline_counter, stage_name, job_names \\ nil) do
    if System.get_env("USE_MOCK_DATA") == "true" do
      Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
      {:ok, %{name: stage_name, counter: 2}}
    else
      # Fetch pipeline instance
      pipeline_instance =
        from(pi in PipelineInstance,
          join: p in assoc(pi, :pipeline),
          where: p.name == ^pipeline_name and pi.counter == ^pipeline_counter,
          preload: [:pipeline]
        )
        |> Repo.one()

      if pipeline_instance do
        pipeline = pipeline_instance.pipeline

        # Find config for this stage
        stage_config =
          from(s in Stage,
            where: s.pipeline_id == ^pipeline.id and s.name == ^stage_name,
            preload: [jobs: :tasks]
          )
          |> Repo.one()

        # Find all stage instances of this stage under the pipeline instance to get the maximum counter
        max_counter =
          from(si in StageInstance,
            where: si.pipeline_instance_id == ^pipeline_instance.id and si.name == ^stage_name,
            select: max(si.counter)
          )
          |> Repo.one() || 0

        # Find latest stage instance to copy settings
        latest_si =
          from(si in StageInstance,
            where: si.pipeline_instance_id == ^pipeline_instance.id and si.name == ^stage_name,
            order_by: [desc: si.counter],
            limit: 1
          )
          |> Repo.one()

        if latest_si && stage_config do
          next_counter = max_counter + 1
          now = DateTime.utc_now()

          # Determine which jobs to run
          jobs_to_run =
            cond do
              is_list(job_names) ->
                Enum.filter(stage_config.jobs, fn j -> j.name in job_names end)

              job_names == :failed || job_names == "failed" ->
                # Fetch previous job instances
                prev_job_instances =
                  from(ji in JobInstance,
                    where: ji.stage_instance_id == ^latest_si.id
                  )
                  |> Repo.all()

                failed_job_names =
                  prev_job_instances
                  |> Enum.filter(fn ji -> ji.result in ["Failed", "Cancelled", "Unknown"] end)
                  |> Enum.map(& &1.name)

                Enum.filter(stage_config.jobs, fn j -> j.name in failed_job_names end)

              true ->
                # Default: rerun all jobs in config
                stage_config.jobs
            end

          if Enum.empty?(jobs_to_run) do
            {:error, :no_jobs_to_run}
          else
            # Mark all previous stage instances for this stage under this pipeline instance as latest_run: false
            from(si in StageInstance,
              where: si.pipeline_instance_id == ^pipeline_instance.id and si.name == ^stage_name
            )
            |> Repo.update_all(set: [latest_run: false])

            result =
              Repo.transaction(fn ->
                new_stage_instance =
                  %StageInstance{}
                  |> StageInstance.changeset(%{
                    pipeline_instance_id: pipeline_instance.id,
                    name: stage_name,
                    counter: next_counter,
                    order_id: latest_si.order_id,
                    state: "Building",
                    result: "Unknown",
                    approval_type: latest_si.approval_type,
                    created_time: now,
                    fetch_materials: latest_si.fetch_materials,
                    clean_working_dir: latest_si.clean_working_dir,
                    latest_run: true,
                    rerun_of_counter: latest_si.counter
                  })
                  |> Repo.insert!()

                scheduled_at = DateTime.to_naive(now)

                job_instances =
                  Enum.map(jobs_to_run, fn job ->
                    %JobInstance{}
                    |> JobInstance.changeset(%{
                      stage_instance_id: new_stage_instance.id,
                      job_id: job.id,
                      name: job.name,
                      state: "Scheduled",
                      result: "Unknown",
                      scheduled_at: scheduled_at,
                      run_on_all_agents: job.run_on_all_agents || false,
                      run_multiple_instance: false,
                      identifier: "#{pipeline.name}/#{pipeline_counter}/#{stage_name}/#{next_counter}/#{job.name}/1"
                    })
                    |> Repo.insert!()
                  end)

                {new_stage_instance, job_instances}
              end)

            case result do
              {:ok, {new_stage_instance, job_instances}} ->
                for ji <- job_instances do
                  job_config = Enum.find(stage_config.jobs, &(&1.id == ji.job_id))
                  build_command = build_command_from_job(job_config)

                  spec = %{
                    "pipeline" => pipeline.name,
                    "pipeline_counter" => pipeline_counter,
                    "stage" => stage_name,
                    "stage_counter" => next_counter,
                    "job" => job_config.name,
                    "resources" => job_config.resources || [],
                    "environments" => [],
                    "build_command" => build_command,
                    "job_instance_id" => ji.id
                  }

                  Scheduler.schedule_job(spec)
                end

                Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
                {:ok, new_stage_instance}

              {:error, reason} ->
                {:error, reason}
            end
          end
        else
          {:error, :stage_not_found}
        end
      else
        {:error, :pipeline_instance_not_found}
      end
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
      stages: Enum.map(pipeline.stages || [], fn s -> %{name: s.name, status: "NotRun", duration: nil} end),
      paused: pipeline.paused,
      paused_by: pipeline.paused_by,
      pause_cause: pipeline.pause_cause,
      paused_at: pipeline.paused_at
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
      stages: filled_stages,
      paused: pipeline.paused,
      paused_by: pipeline.paused_by,
      pause_cause: pipeline.pause_cause,
      paused_at: pipeline.paused_at
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
      res =
        ji
        |> JobInstance.changeset(%{state: "Assigned", agent_uuid: agent_uuid, assigned_at: now})
        |> Repo.update()
      Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
      res
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

    stage = ji.stage_instance

    from(j in JobInstance, where: j.stage_instance_id == ^stage.id)
    |> Repo.all()
    |> maybe_complete_stage(stage, now)

    Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
    :ok
  end

  defp maybe_complete_stage(jobs, stage, now) do
    if Enum.all?(jobs, &(&1.state == "Completed")) do
      stage_result =
        if Enum.any?(jobs, &(&1.result == "Failed" or &1.result == "Cancelled")),
          do: "Failed",
          else: "Passed"

      case stage
           |> StageInstance.changeset(%{
             state: "Completed",
             result: stage_result,
             completed_at: now,
             last_transitioned_time: DateTime.utc_now()
           })
           |> Repo.update() do
        {:ok, updated_stage} ->
          if stage_result == "Passed" do
            trigger_next_stage(updated_stage)
          end
          :ok
        error ->
          error
      end
    end
  end

  defp trigger_next_stage(stage_instance) do
    stage_instance = Repo.preload(stage_instance, [pipeline_instance: [pipeline: :stages]])
    pipeline_instance = stage_instance.pipeline_instance
    pipeline = pipeline_instance.pipeline

    stages = Enum.sort_by(pipeline.stages || [], & &1.id)
    current_idx = Enum.find_index(stages, &(&1.name == stage_instance.name))

    if current_idx && current_idx + 1 < length(stages) do
      next_stage = Enum.at(stages, current_idx + 1)
      now = DateTime.utc_now()

      Repo.transaction(fn ->
        new_stage_instance =
          %StageInstance{}
          |> StageInstance.changeset(%{
            pipeline_instance_id: pipeline_instance.id,
            name: next_stage.name,
            counter: 1,
            order_id: current_idx + 2,
            state: "Building",
            result: "Unknown",
            approval_type: next_stage.approval_type,
            created_time: now,
            fetch_materials: next_stage.fetch_materials,
            clean_working_dir: next_stage.clean_working_directory
          })
          |> Repo.insert!()

        scheduled_at = DateTime.to_naive(now)
        next_stage_config = Repo.preload(next_stage, jobs: :tasks)

        job_instances =
          Enum.map(next_stage_config.jobs, fn job ->
            %JobInstance{}
            |> JobInstance.changeset(%{
              stage_instance_id: new_stage_instance.id,
              job_id: job.id,
              name: job.name,
              state: "Scheduled",
              result: "Unknown",
              scheduled_at: scheduled_at,
              run_on_all_agents: job.run_on_all_agents || false,
              run_multiple_instance: false,
              identifier: "#{pipeline.name}/#{pipeline_instance.counter}/#{next_stage.name}/1/#{job.name}/1"
            })
            |> Repo.insert!()
          end)

        {new_stage_instance, next_stage_config, job_instances}
      end)
      |> case do
        {:ok, {new_si, next_stage_config, job_instances}} ->
          for ji <- job_instances do
            job_config = Enum.find(next_stage_config.jobs, &(&1.id == ji.job_id))
            schedule_job_if_config(pipeline, pipeline_instance.counter, new_si, job_config, ji)
          end
          :ok
        error ->
          error
      end
    else
      :ok
    end
  end

  @doc """
  Lists all SCM materials config from database with preloaded pipelines.
  """
  def list_materials do
    Material
    |> Repo.all()
    |> Repo.preload(:pipelines)
  end

  @doc """
  Creates a pipeline config in the DB.
  """
  def create_pipeline(attrs) do
    %Pipeline{}
    |> Pipeline.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a pipeline config.
  """
  def update_pipeline(%Pipeline{} = pipeline, attrs) do
    pipeline
    |> Pipeline.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a pipeline config.
  """
  def delete_pipeline(%Pipeline{} = pipeline) do
    Repo.delete(pipeline)
  end

  @doc """
  Deletes a pipeline config by its name.
  """
  def delete_pipeline_by_name(name) when is_binary(name) do
    case get_pipeline_by_name(name) do
      nil -> {:error, :not_found}
      pipeline -> Repo.delete(pipeline)
    end
  end

  @doc """
  Creates a stage config.
  """
  def create_stage(attrs) do
    %Stage{}
    |> Stage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a stage config.
  """
  def update_stage(%Stage{} = stage, attrs) do
    stage
    |> Stage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a stage config.
  """
  def delete_stage(%Stage{} = stage) do
    Repo.delete(stage)
  end

  @doc """
  Gets a stage config by id.
  """
  def get_stage(id) when is_integer(id) or is_binary(id), do: Repo.get(Stage, id)

  @doc """
  Creates a job config.
  """
  def create_job(attrs) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a job config.
  """
  def update_job(%Job{} = job, attrs) do
    job
    |> Job.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a job config.
  """
  def delete_job(%Job{} = job) do
    Repo.delete(job)
  end

  @doc """
  Gets a job config by id.
  """
  def get_job(id) when is_integer(id) or is_binary(id), do: Repo.get(Job, id) |> Repo.preload(:tasks)

  @doc """
  Creates a task config.
  """
  def create_task(attrs) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a task config.
  """
  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a task config.
  """
  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  @doc """
  Gets a task config by id.
  """
  def get_task(id) when is_integer(id) or is_binary(id), do: Repo.get(Task, id)

  @doc """
  Adds/associates a material configuration with a pipeline.
  """
  def add_material_to_pipeline(%Pipeline{} = pipeline, %Material{} = material) do
    pipeline = Repo.preload(pipeline, :materials)
    unless Enum.any?(pipeline.materials, &(&1.id == material.id)) do
      pipeline
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:materials, [material | pipeline.materials])
      |> Repo.update()
    else
      {:ok, pipeline}
    end
  end

  @doc """
  Creates a material and links it to a pipeline.
  """
  def create_material_for_pipeline(%Pipeline{} = pipeline, material_attrs) do
    Repo.transaction(fn ->
      string_attrs = Map.new(material_attrs, fn {k, v} -> {to_string(k), v} end)
      url = string_attrs["url"]
      type = string_attrs["type"]

      material =
        case Repo.get_by(Material, type: type, url: url) do
          nil ->
            %Material{}
            |> Material.changeset(string_attrs)
            |> Repo.insert!()
          m ->
            m
            |> Material.changeset(string_attrs)
            |> Repo.update!()
        end

      {:ok, _} = add_material_to_pipeline(pipeline, material)
      material
    end)
  end
end
