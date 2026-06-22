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
  require Logger
  alias ExGoCD.Materials.ScmClient
  alias ExGoCD.Pipelines.CycleDetector
  alias ExGoCD.Pipelines.FanInResolver
  alias ExGoCD.Pipelines.Job
  alias ExGoCD.Pipelines.JobInstance
  alias ExGoCD.Pipelines.Material
  alias ExGoCD.Pipelines.Modification
  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Pipelines.PipelineInstance
  alias ExGoCD.Pipelines.PipelineMaterialRevision
  alias ExGoCD.Pipelines.Stage
  alias ExGoCD.Pipelines.StageInstance
  alias ExGoCD.Pipelines.Task
  alias ExGoCD.Pipelines.Template
  alias ExGoCD.Repo
  alias ExGoCD.Scheduler
  alias ExGoCD.Params
  alias ExGoCD.VsmTracer
  alias ExGoCD.Agents
  alias ExGoCD.AuditLog.Events

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
  Adds a comment to a pipeline instance.
  Stores the comment in the build_cause map under the "comment" key.
  """
  def add_comment(pipeline_name, counter, comment) do
    pi = Repo.one(
      from pi in PipelineInstance,
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and pi.counter == ^counter
    )

    case pi do
      nil -> {:error, :instance_not_found}
      %PipelineInstance{} = instance ->
        build_cause = instance.build_cause || %{}
        updated = Map.put(build_cause, "comment", comment)
        instance
        |> Ecto.Changeset.change(build_cause: updated)
        |> Repo.update()
    end
  end

  @doc """
  Detects config changes between a pipeline instance and its previous run.
  Returns {:ok, diff_map} if config changed, {:ok, nil} if unchanged,
  or {:error, reason} if instance not found.
  """
  def config_diff(pipeline_name, counter) do
    pi = Repo.one(
      from pi in PipelineInstance,
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and pi.counter == ^counter
    )

    case pi do
      nil -> {:error, :instance_not_found}
      instance ->
        current_snapshot = (instance.build_cause || %{})["configSnapshot"]
        previous_snapshot = get_previous_config_snapshot(instance.pipeline_id, counter)

        if current_snapshot && previous_snapshot && current_snapshot != previous_snapshot do
          diff = MapDiff.diff(previous_snapshot, current_snapshot)
          {:ok, diff}
        else
          {:ok, nil}
        end
    end
  end

  defp get_previous_config_snapshot(pipeline_id, current_counter) do
    from(pi in PipelineInstance,
      where: pi.pipeline_id == ^pipeline_id and pi.counter < ^current_counter,
      order_by: [desc: pi.counter],
      limit: 1,
      select: pi.build_cause
    )
    |> Repo.one()
    |> case do
      nil -> nil
      bc -> bc["configSnapshot"]
    end
  end

  @doc """
  Triggers a pipeline run: creates PipelineInstance, StageInstances, JobInstances for the first stage,
  and enqueues each job to the Scheduler. Jobs will be picked up by idle agents.
  Returns {:ok, pipeline_instance} or {:error, changeset}.
  """
  def trigger_pipeline(pipeline_name, options \\ %{}) when is_binary(pipeline_name) and is_map(options) do
    result =
      VsmTracer.trace("pipeline.trigger", %{"pipeline.name" => pipeline_name}, fn ->
        with %Pipeline{} = pipeline <- get_pipeline_by_name(pipeline_name),
             {:paused, false} <- {:paused, pipeline.paused},
             {:locked, false} <- {:locked, pipeline_locked?(pipeline)},
             {:maintenance, false} <- {:maintenance, ExGoCD.MaintenanceMode.enabled?()},
             pipeline = Repo.preload(pipeline, [:materials, :template, stages: [jobs: :tasks]]),
             pipeline = resolve_template_stages(pipeline),
             {:ok, proposed} <- resolve_proposed_revisions(pipeline, options),
             :ok <- FanInResolver.verify_consistency(proposed) do
          trigger_result = do_trigger_pipeline_with_proposed(pipeline, proposed, options)
          # Set pipeline.counter on the span after trigger succeeds
          case trigger_result do
            {:ok, instance} ->
              VsmTracer.set_attr("pipeline.counter", instance.counter)
              VsmTracer.set_status(:ok)
            {:error, _reason} ->
              VsmTracer.set_status({:error, "Pipeline trigger failed"})
          end
          trigger_result
        else
          nil -> {:error, :pipeline_not_found}
          {:paused, true} -> {:error, :pipeline_paused}
          {:locked, true} -> {:error, :pipeline_locked}
          {:maintenance, true} -> {:error, :maintenance_mode}
          {:error, reason} -> {:error, reason}
        end
      end)

    # Emit telemetry for pipeline trigger
    _ = emit_trigger_telemetry(pipeline_name, result)

    result
  end

  @doc """
  If pipeline has a template, loads template stages (with jobs and tasks)
  and swaps them into pipeline.stages. Parameters are NOT interpolated here —
  that happens lazily in the trigger flow.
  """
  def resolve_template_stages(%{template_id: nil} = pipeline), do: pipeline
  def resolve_template_stages(%{template_id: template_id} = pipeline) do
    template = Repo.get!(Template, template_id)
    |> Repo.preload(stages: [jobs: :tasks])
    %{pipeline | stages: template.stages}
  end

  @doc """
  Calculates a 16-character SHA256 fingerprint for a material.
  """
  def material_fingerprint(mat) do
    :crypto.hash(:sha256, "#{mat.type}-#{mat.url || ""}-#{mat.branch || ""}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp resolve_proposed_revisions(pipeline, %{materials: overrides}) when is_list(overrides) do
    case get_proposed_revisions(pipeline) do
      {:ok, proposed} ->
        updated_proposed =
          Enum.reduce(overrides, proposed, fn override, acc ->
            fp = override["fingerprint"] || override[:fingerprint]
            revision = override["revision"] || override[:revision]

            case Enum.find(pipeline.materials || [], &(material_fingerprint(&1) == fp)) do
              nil ->
                acc

              material ->
                mod = get_or_create_modification_for_revision(material, revision)
                type_atom = material_type_to_atom(material.type)
                Map.put(acc, material.id, {type_atom, mod})
            end
          end)

        {:ok, updated_proposed}

      error ->
        error
    end
  end

  defp resolve_proposed_revisions(pipeline, %{"materials" => overrides}) when is_list(overrides) do
    resolve_proposed_revisions(pipeline, %{materials: overrides})
  end

  defp resolve_proposed_revisions(pipeline, _options) do
    get_proposed_revisions(pipeline)
  end

  defp get_or_create_modification_for_revision(material, revision) do
    case Repo.get_by(Modification, material_id: material.id, revision: revision) do
      nil ->
        attrs = %{
          material_id: material.id,
          revision: revision,
          committer_name: "gocd",
          committer_email: "gocd@localhost",
          comment: "Triggered with specific revision",
          modified_time: DateTime.utc_now() |> DateTime.truncate(:second)
        }
        {:ok, mod} = create_modification(attrs)
        mod

      mod ->
        mod
    end
  end

  defp material_type_to_atom("git"), do: :git
  defp material_type_to_atom("dependency"), do: :pipeline
  defp material_type_to_atom("svn"), do: :svn
  defp material_type_to_atom("hg"), do: :hg
  defp material_type_to_atom("p4"), do: :p4
  defp material_type_to_atom("tfs"), do: :tfs
  defp material_type_to_atom(_other), do: :unknown

  @doc """
  Cancels all stuck Scheduled/Building jobs. Returns count of cancelled jobs.
  Stuck = Scheduled with no agent assignment after 5 min, or Building with no agent.
  """
  def cleanup_stuck_jobs do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -300, :second)

    # Cancel Scheduled jobs older than 5 min with no agent
    scheduled = from(ji in JobInstance,
      where: ji.state == "Scheduled" and is_nil(ji.agent_uuid) and ji.inserted_at < ^cutoff
    ) |> Repo.all()

    # Cancel Building jobs where agent is no longer connected
    building = from(ji in JobInstance,
      where: ji.state == "Building"
    ) |> Repo.all()

    stuck = scheduled ++ Enum.filter(building, fn ji ->
      is_nil(ji.agent_uuid)
    end)

    Enum.each(stuck, fn ji ->
      ji |> JobInstance.changeset(%{state: "Completed", result: "Cancelled", completed_at: now}) |> Repo.update!()
      # Update stage if all jobs done
      cancel_stage_if_all_done(ji.stage_instance_id)
    end)

    length(stuck)
  end

  @doc """
  Resets a pipeline\'s latest instance to a clean state.
  """
  def reset_pipeline(pipeline_name) do
    pipeline = get_pipeline_by_name(pipeline_name)
    if pipeline do
      from(ji in JobInstance,
        join: si in assoc(ji, :stage_instance),
        join: pi in assoc(si, :pipeline_instance),
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and ji.state in ["Scheduled", "Assigned", "Building", "Preparing"],
        select: ji
      ) |> Repo.all()
      |> Enum.each(fn ji ->
        ji |> JobInstance.changeset(%{state: "Completed", result: "Cancelled"}) |> Repo.update!()
      end)
      {:ok, pipeline_name}
    else
      {:error, :not_found}
    end
  end

  defp cancel_stage_if_all_done(stage_instance_id) do
    stage = Repo.get!(StageInstance, stage_instance_id) |> Repo.preload(:job_instances)
    if Enum.all?(stage.job_instances, &(&1.state in ["Completed", "Failed"])) do
      stage |> StageInstance.changeset(%{state: "Completed", result: "Cancelled"}) |> Repo.update!()
    end
  end
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

  @doc """
  Unlocks a locked pipeline.
  """
  def unlock_pipeline(pipeline_name) when is_binary(pipeline_name) do
    case get_pipeline_by_name(pipeline_name) do
      nil -> {:error, :pipeline_not_found}
      pipeline ->
        pipeline
        |> Pipeline.changeset(%{locked: false})
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
  Approves an awaiting manual stage instance, transitioning it to Building and scheduling its jobs.
  """
  def approve_stage(pipeline_name, pipeline_counter, stage_name) when is_binary(pipeline_name) and is_integer(pipeline_counter) and is_binary(stage_name) do
    query =
      from si in StageInstance,
        join: pi in assoc(si, :pipeline_instance),
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and pi.counter == ^pipeline_counter and si.name == ^stage_name and si.state == "Awaiting",
        preload: [pipeline_instance: :pipeline]

    case Repo.one(query) do
      nil ->
        {:error, :stage_not_awaiting_approval}

      stage_instance ->
        pipeline = stage_instance.pipeline_instance.pipeline
        pipeline_config = Repo.preload(pipeline, stages: [jobs: :tasks])
        stage_config = Enum.find(pipeline_config.stages, &(&1.name == stage_instance.name))

        if is_nil(stage_config) do
          {:error, :stage_config_not_found}
        else
          now = DateTime.utc_now()
          scheduled_at = DateTime.to_naive(now)

          result =
            Repo.transaction(fn ->
              # Update StageInstance state to "Building"
              {:ok, updated_si} =
                stage_instance
                |> StageInstance.changeset(%{
                  state: "Building",
                  last_transitioned_time: now
                })
                |> Repo.update()

              # Create job instances
              job_instances =
                insert_next_job_instances(
                  updated_si.id,
                  stage_config.jobs,
                  pipeline.name,
                  pipeline_counter,
                  stage_config.name,
                  scheduled_at
                )

              {updated_si, job_instances}
            end)

          case result do
            {:ok, {updated_si, job_instances}} ->
              # Schedule jobs
              schedule_next_jobs(
                pipeline,
                pipeline_counter,
                updated_si,
                stage_config.jobs,
                job_instances,
                pipeline.parameters || %{}
              )

              Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
              {:ok, updated_si}

            {:error, reason} ->
              {:error, reason}
          end
        end
    end
  end

  @doc """
  Cancels a stage by marking all its building/scheduled job instances as Cancelled.
  """
  def cancel_stage(pipeline_name, pipeline_counter, stage_name)
      when is_binary(pipeline_name) and is_integer(pipeline_counter) and is_binary(stage_name) do
    import Ecto.Query

    query =
      from si in StageInstance,
        join: pi in assoc(si, :pipeline_instance),
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and pi.counter == ^pipeline_counter and si.name == ^stage_name,
        preload: :job_instances,
        limit: 1

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      si ->
        cancel_stage_transaction(si)
        Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
        {:ok, si}
    end
  end

  defp cancel_stage_transaction(si) do
    Repo.transaction(fn ->
      Repo.update!(StageInstance.changeset(si, %{state: "Cancelled", result: "Cancelled"}))

      Enum.each(si.job_instances, fn ji ->
        if ji.state in ["Scheduled", "Assigned", "Preparing", "Building"] do
          Repo.update!(JobInstance.changeset(ji, %{state: "Cancelled", result: "Cancelled"}))
        end
      end)
    end)
  end

  @doc """
  Checks if a pipeline is currently building.
  """
  def pipeline_building?(pipeline_id) do
    query =
      from pi in PipelineInstance,
        join: si in assoc(pi, :stage_instances),
        where: pi.pipeline_id == ^pipeline_id and si.state in ["Building", "Awaiting"],
        select: count(pi.id)

    Repo.one(query) > 0
  end

  @doc """
  Checks if a pipeline is locked.
  """
  def pipeline_locked?(pipeline) do
    case pipeline.lock_behavior do
      "none" ->
        false

      "unlockWhenFinished" ->
        pipeline_building?(pipeline.id)

      "lockOnFailure" ->
        pipeline.locked or pipeline_building?(pipeline.id)

      _ ->
        false
    end
  end

  defp get_proposed_revisions(pipeline) do
    Enum.reduce_while(pipeline.materials || [], {:ok, %{}}, &propose_material_revision/2)
  end

  defp propose_material_revision(material, {:ok, acc}) do
    case material.type do
      "git" ->
        mod = get_or_create_latest_modification(material)
        {:cont, {:ok, Map.put(acc, material.id, {:git, mod})}}

      "svn" ->
        mod = get_or_create_latest_modification(material)
        {:cont, {:ok, Map.put(acc, material.id, {:svn, mod})}}

      "hg" ->
        mod = get_or_create_latest_modification(material)
        {:cont, {:ok, Map.put(acc, material.id, {:hg, mod})}}

      "p4" ->
        mod = get_or_create_latest_modification(material)
        {:cont, {:ok, Map.put(acc, material.id, {:p4, mod})}}

      "dependency" ->
        resolve_proposed_dependency(material, acc)

      _ ->
        {:cont, {:ok, acc}}
    end
  end

  defp resolve_proposed_dependency(material, acc) do
    case get_latest_passed_instance(material.url) do
      nil ->
        {:halt, {:error, {:upstream_not_passed, material.url}}}
      pi ->
        {:cont, {:ok, Map.put(acc, material.id, {:pipeline, pi})}}
    end
  end

  defp get_or_create_latest_modification(material) do
    case get_latest_modification(material.id) do
      nil ->
        sha = get_material_revision(material)
        attrs = %{
          material_id: material.id,
          revision: sha,
          committer_name: "gocd",
          committer_email: "gocd@localhost",
          comment: "Initial commit",
          modified_time: DateTime.utc_now()
        }
        {:ok, mod} = create_modification(attrs)
        mod
      mod ->
        mod
    end
  end

  defp get_material_revision(mat) do
    # Only attempt real SCM lookup for materials with non-empty URLs
    if mat.url && mat.url != "" do
      case ScmClient.latest_revision(mat) do
        {:ok, %{revision: sha}} -> sha
        _ -> "HEAD"
      end
    else
      "HEAD"
    end
  end

  defp get_latest_passed_instance(pipeline_name) do
    from(pi in PipelineInstance,
      join: p in assoc(pi, :pipeline),
      join: si in assoc(pi, :stage_instances),
      where: p.name == ^pipeline_name,
      order_by: [desc: pi.counter],
      preload: [:pipeline, :stage_instances]
    )
    |> Repo.all()
    |> Enum.find(fn pi ->
      not Enum.empty?(pi.stage_instances) and
        Enum.all?(pi.stage_instances, &(&1.state == "Completed" and &1.result == "Passed"))
    end)
  end

  defp do_trigger_pipeline_with_proposed(pipeline, proposed, options) do
    counter = next_counter(pipeline.id)
    now = DateTime.utc_now()
    params = Params.merge_params(pipeline.parameters, options)
    label = pipeline.label_template
    |> Params.interpolate(params)
    |> String.replace("${COUNT}", to_string(counter))
    natural_order = counter * 1.0

    material_revisions = build_material_revisions_map(pipeline, proposed)

    env_vars = Map.get(options, :environment_variables) || Map.get(options, "environment_variables")
    env_vars = if is_list(env_vars), do: Params.interpolate(env_vars, params), else: env_vars

    build_cause = %{
      "approver" => "anonymous",
      "triggerMessage" => "Triggered from dashboard",
      "triggerForced" => false,
      "materialRevisions" => material_revisions,
      "configSnapshot" => pipeline_config_snapshot(pipeline)
    }

    build_cause =
      if is_list(env_vars) do
        Map.put(build_cause, "environmentVariables", env_vars)
      else
        build_cause
      end

    # Compute idle agent count OUTSIDE the transaction (DB query)
    idle_count = Agents.count_idle()

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

        insert_pipeline_material_revisions(instance.id, proposed)

        stages_ordered = Enum.sort_by(pipeline.stages, & &1.id)
        first_stage = List.first(stages_ordered)
        if is_nil(first_stage), do: raise("Pipeline has no stages")

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
          Enum.flat_map(first_stage.jobs, fn job ->
            count = instance_count_for_job(job, idle_count)
            run_on_all = job.run_on_all_agents || false
            run_multiple = job.run_instance_count not in [nil, ""]

            for i <- 1..count do
              insert_job_instance(job, pipeline, stage_instance, first_stage, scheduled_at,
                run_on_all: run_on_all, run_multiple: run_multiple, count: count, run_index: i, counter: counter)
            end
          end)

        {instance, first_stage, stage_instance, job_instances}
      end)

    case result do
      {:ok, {instance, first_stage, stage_instance, job_instances}} ->
        for ji <- job_instances do
          job_config = Enum.find(first_stage.jobs, &(&1.id == ji.job_id))
          schedule_job_if_config(pipeline, counter, stage_instance, job_config, ji, params)
        end
        Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
        Events.pipeline_triggered("anonymous", pipeline.name, counter)
        {:ok, instance}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Determines how many JobInstances to create for a job config.
  # - run_on_all_agents: one per idle agent
  # - run_instance_count set (not nil): N parallel instances
  # - default: 1
  defp instance_count_for_job(job, idle_count) do
    cond do
      job.run_on_all_agents ->
        max(idle_count, 1)

      job.run_instance_count not in [nil, ""] ->
        case job.run_instance_count do
          "all" -> max(idle_count, 1)
          str when is_binary(str) ->
            case Integer.parse(str) do
              {n, _} -> max(n, 1)
              :error -> 1
            end
          n when is_integer(n) -> max(n, 1)
          _ -> 1
        end

      true -> 1
    end
  end

  defp insert_job_instance(job, pipeline, stage_instance, first_stage, scheduled_at, opts) do
    run_multiple = Keyword.get(opts, :run_multiple, false)
    count = Keyword.get(opts, :count, 1)
    i = Keyword.get(opts, :run_index, 1)

    identifier_suffix = if run_multiple and count > 1, do: "/run-#{i}", else: ""
    identifier = "#{pipeline.name}/#{Keyword.get(opts, :counter, 1)}/#{first_stage.name}/1/#{job.name}/1#{identifier_suffix}"

    %JobInstance{}
    |> JobInstance.changeset(%{
      stage_instance_id: stage_instance.id,
      job_id: job.id,
      name: job.name,
      state: "Scheduled",
      result: "Unknown",
      scheduled_at: scheduled_at,
      run_on_all_agents: Keyword.get(opts, :run_on_all, false),
      run_multiple_instance: run_multiple,
      identifier: identifier
    })
    |> Repo.insert!()
  end

  defp build_material_revisions_map(pipeline, proposed) do
    Enum.map(pipeline.materials || [], fn material ->
      ref = Map.get(proposed, material.id)
      revision =
        case ref do
          {:git, mod} -> mod.revision
          {:pipeline, pi} -> "#{pi.pipeline.name}/#{pi.counter}"
          _ -> "HEAD"
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

  defp insert_pipeline_material_revisions(pipeline_instance_id, proposed) do
    Enum.each(proposed, fn {material_id, ref} ->
      attrs =
        case ref do
          {:git, mod} ->
            %{
              pipeline_instance_id: pipeline_instance_id,
              material_id: material_id,
              modification_id: mod.id,
              revision: mod.revision
            }

          {:pipeline, pi} ->
            %{
              pipeline_instance_id: pipeline_instance_id,
              material_id: material_id,
              parent_pipeline_instance_id: pi.id,
              revision: "#{pi.pipeline.name}/#{pi.counter}"
            }
        end

      %PipelineMaterialRevision{}
      |> PipelineMaterialRevision.changeset(attrs)
      |> Repo.insert!()
    end)
  end

  defp schedule_job_if_config(_pipeline, _counter, _stage, nil, _ji, _params), do: :noop

  defp schedule_job_if_config(pipeline, counter, stage, job_config, ji, params) do
    build_command = build_command_from_job(job_config, params)

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

  defp build_command_from_job(job, params \\ %{}) do
    first_task = List.first(job.tasks || [])
    if first_task && first_task.type == "exec" do
      %{
        "name" => first_task.type,
        "command" => Params.interpolate(first_task.command || "echo", params),
        "args" => Params.interpolate(first_task.arguments || [], params)
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
  Lists pipeline instances for a given pipeline, newest first.
  """
  def list_pipeline_instances(pipeline_id, opts \\ []) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 10)

    from(pi in PipelineInstance,
      where: pi.pipeline_id == ^pipeline_id,
      order_by: [desc: :counter],
      offset: ^offset,
      limit: ^limit,
      preload: [:pipeline, stage_instances: [job_instances: :job]]
    )
    |> Repo.all()
  end

  @doc """
  Counts total pipeline instances for a given pipeline.
  """
  def count_pipeline_instances(pipeline_id) do
    from(pi in PipelineInstance,
      where: pi.pipeline_id == ^pipeline_id,
      select: count(pi.id)
    )
    |> Repo.one()
  end

  @doc """
  Gets the latest modification for a given material.
  """
  def get_latest_modification(material_id) do
    query =
      from m in Modification,
        where: m.material_id == ^material_id,
        order_by: [desc: :modified_time, desc: :id],
        limit: 1

    Repo.one(query)
  end

  @doc """
  Creates a modification record.
  """
  def create_modification(attrs \\ %{}) do
    %Modification{}
    |> Modification.changeset(attrs)
    |> Repo.insert()
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
      modifications = Map.get(to_rev_info, :modifications, [])

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
      do_rerun_stage(pipeline_name, pipeline_counter, stage_name, job_names)
    end
  end

  defp do_rerun_stage(pipeline_name, pipeline_counter, stage_name, job_names) do
    with %PipelineInstance{} = pi <- get_pipeline_instance_by_name(pipeline_name, pipeline_counter),
         %Stage{} = stage_config <- get_stage_config(pi.pipeline_id, stage_name),
         %StageInstance{} = latest_si <- get_latest_stage_instance(pi.id, stage_name) do
      max_counter = get_max_stage_counter(pi.id, stage_name)
      perform_rerun_stage(pi, stage_config, latest_si, max_counter, job_names)
    else
      nil -> {:error, :not_found}
    end
  end

  defp get_pipeline_instance_by_name(name, counter) do
    from(pi in PipelineInstance,
      join: p in assoc(pi, :pipeline),
      where: p.name == ^name and pi.counter == ^counter,
      preload: [:pipeline]
    )
    |> Repo.one()
  end

  defp get_stage_config(pipeline_id, name) do
    from(s in Stage,
      where: s.pipeline_id == ^pipeline_id and s.name == ^name,
      preload: [jobs: :tasks]
    )
    |> Repo.one()
  end

  defp get_latest_stage_instance(pi_id, name) do
    from(si in StageInstance,
      where: si.pipeline_instance_id == ^pi_id and si.name == ^name,
      order_by: [desc: si.counter],
      limit: 1
    )
    |> Repo.one()
  end

  defp get_max_stage_counter(pi_id, name) do
    from(si in StageInstance,
      where: si.pipeline_instance_id == ^pi_id and si.name == ^name,
      select: max(si.counter)
    )
    |> Repo.one() || 0
  end

  defp perform_rerun_stage(pi, stage_config, latest_si, max_counter, job_names) do
    jobs_to_run = select_jobs_to_run(stage_config.jobs, latest_si.id, job_names)

    if Enum.empty?(jobs_to_run) do
      {:error, :no_jobs_to_run}
    else
      next_counter = max_counter + 1
      now = DateTime.utc_now()

      mark_previous_stage_instances_not_latest(pi.id, latest_si.name)

      result =
        Repo.transaction(fn ->
          insert_rerun_instances(pi, stage_config, latest_si, next_counter, jobs_to_run, now)
        end)

      case result do
        {:ok, {new_stage_instance, job_instances}} ->
          enqueue_rerun_jobs(pi.pipeline, pi.counter, latest_si.name, next_counter, stage_config.jobs, job_instances)
          Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
          {:ok, new_stage_instance}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp select_jobs_to_run(jobs, _latest_si_id, job_names) when is_list(job_names) do
    Enum.filter(jobs, fn j -> j.name in job_names end)
  end
  defp select_jobs_to_run(jobs, latest_si_id, job_names) when job_names in [:failed, "failed"] do
    prev_job_instances = from(ji in JobInstance, where: ji.stage_instance_id == ^latest_si_id) |> Repo.all()
    failed_names =
      prev_job_instances
      |> Enum.filter(fn ji -> ji.result in ["Failed", "Cancelled", "Unknown"] end)
      |> Enum.map(& &1.name)

    Enum.filter(jobs, fn j -> j.name in failed_names end)
  end
  defp select_jobs_to_run(jobs, _latest_si_id, _), do: jobs

  defp mark_previous_stage_instances_not_latest(pi_id, name) do
    from(si in StageInstance,
      where: si.pipeline_instance_id == ^pi_id and si.name == ^name
    )
    |> Repo.update_all(set: [latest_run: false])
  end

  defp insert_rerun_instances(pi, _stage_config, latest_si, next_counter, jobs_to_run, now) do
    new_stage_instance =
      %StageInstance{}
      |> StageInstance.changeset(%{
        pipeline_instance_id: pi.id,
        name: latest_si.name,
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
          identifier: "#{pi.pipeline.name}/#{pi.counter}/#{latest_si.name}/#{next_counter}/#{job.name}/1"
        })
        |> Repo.insert!()
      end)

    {new_stage_instance, job_instances}
  end

  defp enqueue_rerun_jobs(pipeline, pipeline_counter, stage_name, next_counter, jobs_config, job_instances) do
    for ji <- job_instances do
      job_config = Enum.find(jobs_config, &(&1.id == ji.job_id))
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
      paused_at: pipeline.paused_at,
      config_repo_id: pipeline.config_repo_id
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
      paused_at: pipeline.paused_at,
      config_repo_id: pipeline.config_repo_id
    }
  end

  defp stage_status(%StageInstance{state: "Awaiting"}), do: "Awaiting"
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

  @doc """
  Determines the status of a pipeline instance based on its stage instances.
  """
  def pipeline_instance_status(instance) do
    stages = instance.stage_instances || []
    cond do
      Enum.any?(stages, fn s -> s.state in ["Building", "Awaiting"] end) -> "Building"
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
      # Preload to get pipeline/ stage context for span attributes
      si =
        from(si in ExGoCD.Pipelines.StageInstance,
          where: si.id == ^ji.stage_instance_id,
          preload: :pipeline_instance
        )
        |> Repo.one()

      pipeline_name = si && si.pipeline_instance && si.pipeline_instance.pipeline_id &&
        (from(p in ExGoCD.Pipelines.Pipeline, where: p.id == ^si.pipeline_instance.pipeline_id, select: p.name) |> Repo.one())
      pipeline_counter = si && si.pipeline_instance && si.pipeline_instance.counter

      VsmTracer.trace("job.assign", %{
        "job.name" => ji.name,
        "agent.uuid" => agent_uuid,
        "job.instance_id" => job_instance_id,
        "pipeline.name" => pipeline_name,
        "pipeline.counter" => pipeline_counter,
        "stage.name" => (si && si.name)
      }, fn ->
        now = NaiveDateTime.utc_now()
        res =
          ji
          |> JobInstance.changeset(%{state: "Assigned", agent_uuid: agent_uuid, assigned_at: now})
          |> Repo.update()
        Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
        case res do
          {:ok, _} -> VsmTracer.set_status(:ok)
          {:error, cs} -> VsmTracer.set_status({:error, "job assign failed: #{inspect(cs.errors)}"})
        end
        res
      end)
    else
      {:error, :not_found}
    end
  end

  @doc """
  Marks a job instance as completed (state Completed, result, completed_at).
  If all jobs in the stage are completed, marks the stage instance completed.
  """
  def complete_job_instance(job_instance_id, result) when is_integer(job_instance_id) do
    ji = Repo.get(JobInstance, job_instance_id) |> Repo.preload(stage_instance: :pipeline_instance)
    if ji do
      pipeline_name = ji.stage_instance && ji.stage_instance.pipeline_instance &&
        (from(p in ExGoCD.Pipelines.Pipeline, where: p.id == ^ji.stage_instance.pipeline_instance.pipeline_id, select: p.name) |> Repo.one())

      VsmTracer.trace("job.complete", %{
        "job.name" => ji.name,
        "job.result" => result,
        "job.instance_id" => job_instance_id,
        "pipeline.name" => pipeline_name,
        "pipeline.counter" => (ji.stage_instance && ji.stage_instance.pipeline_instance && ji.stage_instance.pipeline_instance.counter),
        "stage.name" => (ji.stage_instance && ji.stage_instance.name)
      }, fn ->
        # Set span status: Ok if Passed, Error otherwise
        case result do
          "Passed" -> VsmTracer.set_status(:ok)
          _ -> VsmTracer.set_status({:error, result})
        end

        do_complete_job_instance(ji, result)
        :ok
      end)
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
      do_complete_stage(jobs, stage, now)
    end
  end

  defp do_complete_stage(jobs, stage, now) do
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
        maybe_trigger_next_stage(updated_stage, stage_result)

        stage_loaded = Repo.preload(updated_stage, [pipeline_instance: :pipeline])
        pipeline = stage_loaded.pipeline_instance.pipeline

        if stage_result == "Failed" and pipeline.lock_behavior == "lockOnFailure" do
          pipeline
          |> Pipeline.changeset(%{locked: true})
          |> Repo.update()
        end

        if stage_result == "Passed" do
          check_and_trigger_downstreams(updated_stage)
        end
        :ok
      error ->
        error
    end
  end

  defp maybe_trigger_next_stage(updated_stage, "Passed") do
    trigger_next_stage(updated_stage)
  end
  defp maybe_trigger_next_stage(_updated_stage, _), do: :ok

  defp trigger_next_stage(stage_instance) do
    stage_instance = Repo.preload(stage_instance, [pipeline_instance: [pipeline: :stages]])
    pipeline_instance = stage_instance.pipeline_instance
    pipeline = pipeline_instance.pipeline

    stages = Enum.sort_by(pipeline.stages || [], & &1.id)
    current_idx = Enum.find_index(stages, &(&1.name == stage_instance.name))

    if current_idx && current_idx + 1 < length(stages) do
      next_stage = Enum.at(stages, current_idx + 1)
      do_trigger_next_stage(pipeline, pipeline_instance, next_stage, current_idx)
    else
      :ok
    end
  end

  defp do_trigger_next_stage(pipeline, pipeline_instance, next_stage, current_idx) do
    now = DateTime.utc_now()

    if next_stage.approval_type == "manual" do
      case Repo.transaction(fn ->
             insert_next_stage_instance(pipeline_instance.id, next_stage, current_idx, now)
           end) do
        {:ok, _new_si} ->
          Phoenix.PubSub.broadcast(ExGoCD.PubSub, "pipelines:updates", :pipelines_updated)
          :ok
        error ->
          error
      end
    else
      Repo.transaction(fn ->
        new_stage_instance = insert_next_stage_instance(pipeline_instance.id, next_stage, current_idx, now)
        scheduled_at = DateTime.to_naive(now)
        next_stage_config = Repo.preload(next_stage, jobs: :tasks)
        job_instances = insert_next_job_instances(new_stage_instance.id, next_stage_config.jobs, pipeline.name, pipeline_instance.counter, next_stage.name, scheduled_at)
        {new_stage_instance, next_stage_config, job_instances}
      end)
      |> case do
        {:ok, {new_si, next_stage_config, job_instances}} ->
          schedule_next_jobs(pipeline, pipeline_instance.counter, new_si, next_stage_config.jobs, job_instances, pipeline.parameters || %{})
          :ok
        error ->
          error
      end
    end
  end

  defp insert_next_stage_instance(pipeline_instance_id, next_stage, current_idx, now) do
    state = if next_stage.approval_type == "manual", do: "Awaiting", else: "Building"

    %StageInstance{}
    |> StageInstance.changeset(%{
      pipeline_instance_id: pipeline_instance_id,
      name: next_stage.name,
      counter: 1,
      order_id: current_idx + 2,
      state: state,
      result: "Unknown",
      approval_type: next_stage.approval_type,
      created_time: now,
      fetch_materials: next_stage.fetch_materials,
      clean_working_dir: next_stage.clean_working_directory
    })
    |> Repo.insert!()
  end

  defp insert_next_job_instances(stage_instance_id, jobs, pipeline_name, pipeline_counter, stage_name, scheduled_at) do
    Enum.map(jobs, fn job ->
      %JobInstance{}
      |> JobInstance.changeset(%{
        stage_instance_id: stage_instance_id,
        job_id: job.id,
        name: job.name,
        state: "Scheduled",
        result: "Unknown",
        scheduled_at: scheduled_at,
        run_on_all_agents: job.run_on_all_agents || false,
        run_multiple_instance: false,
        identifier: "#{pipeline_name}/#{pipeline_counter}/#{stage_name}/1/#{job.name}/1"
      })
      |> Repo.insert!()
    end)
  end

  defp schedule_next_jobs(pipeline, counter, new_si, job_configs, job_instances, params) do
    for ji <- job_instances do
      job_config = Enum.find(job_configs, &(&1.id == ji.job_id))
      schedule_job_if_config(pipeline, counter, new_si, job_config, ji, params)
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
    Repo.transaction(fn ->
      with {:ok, pipeline} <- %Pipeline{} |> Pipeline.changeset(attrs) |> Repo.insert(),
           :ok <- CycleDetector.check_dependency_cycles() do
        pipeline
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates a pipeline config.
  """
  def update_pipeline(%Pipeline{} = pipeline, attrs) do
    Repo.transaction(fn ->
      with {:ok, updated} <- pipeline |> Pipeline.changeset(attrs) |> Repo.update(),
           :ok <- CycleDetector.check_dependency_cycles() do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates a material config.
  """
  def update_material(%Material{} = material, attrs) do
    Repo.transaction(fn ->
      with {:ok, updated} <- material |> Material.changeset(attrs) |> Repo.update(),
           :ok <- CycleDetector.check_dependency_cycles() do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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

      case CycleDetector.check_dependency_cycles() do
        :ok -> material
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp check_and_trigger_downstreams(stage_instance) do
    stage_instance = Repo.preload(stage_instance, [pipeline_instance: [pipeline: :stages]])
    pipeline_instance = stage_instance.pipeline_instance
    pipeline = pipeline_instance.pipeline

    stages = Enum.sort_by(pipeline.stages || [], & &1.id)
    current_idx = Enum.find_index(stages, &(&1.name == stage_instance.name))

    if current_idx && current_idx + 1 == length(stages) do
      trigger_completed_downstreams(pipeline.name)
    end
  end

  defp trigger_completed_downstreams(pipeline_name) do
    downstreams = Repo.all(
      from p in Pipeline,
        join: m in assoc(p, :materials),
        where: m.type == "dependency" and m.url == ^pipeline_name,
        preload: [:materials, stages: :jobs]
    )

    Enum.each(downstreams, &maybe_trigger_downstream(&1, pipeline_name))
  end

  defp maybe_trigger_downstream(dp, upstream_name) do
    # Fan-in gate: only trigger if ALL dependency materials have passed
    if all_dependencies_passed?(dp) do
      Logger.info("[Pipelines] Downstream check: triggering #{dp.name} due to completion of #{upstream_name}")
      case trigger_pipeline(dp.name) do
        {:ok, _instance} ->
          Logger.info("[Pipelines] Downstream check: successfully triggered #{dp.name}")
        {:error, reason} ->
          Logger.warning("[Pipelines] Downstream check: could not trigger #{dp.name}: #{inspect(reason)}")
      end
    else
      Logger.info("[Pipelines] Downstream check: waiting for all deps of #{dp.name} before triggering")
    end
  end

  # Checks whether all dependency materials for this pipeline have at least
  # one completed (passed) stage instance.
  defp all_dependencies_passed?(dp) do
    deps = Repo.preload(dp, :materials).materials || []
    dep_materials = Enum.filter(deps, &(&1.type == "dependency"))

    Enum.all?(dep_materials, fn dep_mat ->
      upstream_name = dep_mat.url
      # Check if there's at least one passed pipeline instance for this upstream
      Repo.exists?(
        from pi in PipelineInstance,
          join: p in assoc(pi, :pipeline),
          join: si in assoc(pi, :stage_instances),
          where: p.name == ^upstream_name and si.state == "Completed" and si.result == "Passed"
      )
    end)
  end

  # Emit OpenTelemetry telemetry events for pipeline triggers.
  defp emit_trigger_telemetry(pipeline_name, {:ok, %PipelineInstance{counter: counter}}) do
    :telemetry.execute([:ex_gocd, :pipeline, :trigger], %{count: 1}, %{
      pipeline_name: pipeline_name,
      counter: counter,
      status: :ok
    })
  end

  defp emit_trigger_telemetry(pipeline_name, {:error, reason}) do
    :telemetry.execute([:ex_gocd, :pipeline, :trigger], %{count: 1}, %{
      pipeline_name: pipeline_name,
      counter: 0,
      status: :error,
      error: reason
    })
  end

  defp emit_trigger_telemetry(_pipeline_name, _), do: :ok

  # ── Template CRUD ─────────────────────────────────────────────────

  def list_templates do
    Repo.all(Template) |> Repo.preload(:pipelines)
  end

  def get_template_by_name(name) do
    Repo.get_by(Template, name: name)
  end

  def create_template(attrs) do
    %Template{}
    |> Template.changeset(attrs)
    |> Repo.insert()
  end

  def update_template(%Template{} = template, attrs) do
    template
    |> Template.changeset(attrs)
    |> Repo.update()
  end

  def delete_template(%Template{} = template) do
    Repo.delete(template)
  end

  @doc """
  Generates a config snapshot of the pipeline at trigger time.
  Used to detect config changes between pipeline runs (Config Diff / Compare).
  """
  def pipeline_config_snapshot(%Pipeline{} = pipeline) do
    %{
      "name" => pipeline.name,
      "group" => pipeline.group,
      "labelTemplate" => pipeline.label_template,
      "lockBehavior" => pipeline.lock_behavior,
      "trackingTool" => pipeline.tracking_tool,
      "timer" => pipeline.timer,
      "environmentVariables" => (pipeline.secure_variables || %{}) |> Map.merge(pipeline.parameters || %{}),
      "materials" => Enum.map(pipeline.materials || [], &material_snapshot/1),
      "stages" => Enum.map(pipeline.stages || [], &stage_snapshot/1)
    }
  end

  defp material_snapshot(mat) do
    %{
      "name" => Map.get(mat, :name),
      "type" => Map.get(mat, :type),
      "url" => Map.get(mat, :url) || "",
      "branch" => Map.get(mat, :branch) || "",
      "fingerprint" => Map.get(mat, :fingerprint) || material_fingerprint(mat)
    }
  end

  defp stage_snapshot(stage) do
    %{
      "name" => Map.get(stage, :name),
      "approvalType" => Map.get(stage, :approval_type) || "success",
      "environmentVariables" => Map.get(stage, :environment_variables) || %{},
      "secureVariables" => Map.get(stage, :secure_variables) || %{},
      "jobs" => (Map.get(stage, :jobs) || []) |> Enum.map(&job_snapshot/1)
    }
  end

  defp job_snapshot(job) do
    %{
      "name" => Map.get(job, :name),
      "timeout" => Map.get(job, :timeout),
      "runInstanceCount" => Map.get(job, :run_instance_count),
      "resources" => Map.get(job, :resources) || [],
      "environmentVariables" => Map.get(job, :environment_variables) || %{},
      "secureVariables" => Map.get(job, :secure_variables) || %{},
      "tasks" => (Map.get(job, :tasks) || []) |> Enum.map(&task_snapshot/1)
    }
  end

  defp task_snapshot(task) do
    type = Map.get(task, :type) || "unknown"
    base = %{"type" => type}

    attrs = Map.get(task, :attrs) || %{}
    case type do
      "exec" -> Map.put(base, "command", Map.get(attrs, "command") || Map.get(attrs, :command) || "")
      _ -> Map.put(base, "attrs", attrs |> Map.drop(["command", :command]))
    end
  end
end
