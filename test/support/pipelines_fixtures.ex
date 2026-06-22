defmodule ExGoCD.PipelinesFixtures do
  @moduledoc """
  Centralized database fixtures for pipeline-related tests.

  Follows the Phoenix Testing Contexts guide pattern: a shared module of
  DB-inserting helpers that any test file can import. Consolidates what was
  previously duplicated as `defp insert_*` functions across 8 test files.
  """

  alias ExGoCD.Pipelines.{
    Job,
    JobInstance,
    Material,
    Modification,
    Pipeline,
    PipelineInstance,
    PipelineMaterialRevision,
    Stage,
    StageInstance,
    Task,
    Template
  }
  alias ExGoCD.Repo

  # ═══════════════════════════════════════════════════════════════════
  # Pipeline config inserters
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Inserts a minimal pipeline config record.

  ## Options
    - `:group` — defaults to `"test"`
    - `:label_template` — defaults to `"${COUNT}"`
    - `:lock_behavior` — defaults to `"none"`
    - `:template_id` — optional template association
  """
  def insert_pipeline(name, opts \\ []) do
    %Pipeline{}
    |> Pipeline.changeset(%{
      name: name,
      group: Keyword.get(opts, :group, "test"),
      label_template: Keyword.get(opts, :label_template, "${COUNT}"),
      lock_behavior: Keyword.get(opts, :lock_behavior, "none"),
      template_id: Keyword.get(opts, :template_id)
    })
    |> Repo.insert!()
  end

  @doc """
  Inserts a pipeline with one stage and `job_count` jobs (each with an exec task).
  Returns `{pipeline, stage, jobs}` — pipeline is preloaded with `[stages: [jobs: :tasks]]`.
  """
  def insert_pipeline_with_jobs(name, job_count) when job_count >= 1 do
    pipeline = insert_pipeline(name)
    stage = insert_stage(pipeline.id, "build", approval_type: "success")

    jobs =
      for i <- 1..job_count do
        job_name = "job-#{i}"
        job = Repo.insert!(%Job{} |> Job.changeset(%{name: job_name, stage_id: stage.id, resources: []}))
        Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: [job_name], job_id: job.id}))
        job
      end

    pipeline = Repo.preload(pipeline, stages: [jobs: :tasks])
    stage = List.first(pipeline.stages)
    {pipeline, stage, jobs}
  end

  @doc """
  Inserts a pipeline using a template with one stage and `job_count` jobs.
  Returns `{pipeline, %{template: template, stage: stage, jobs: jobs}}`.
  """
  def insert_pipeline_with_template(pipeline_name, template_name, job_count) do
    template = Repo.insert!(%Template{} |> Template.changeset(%{name: template_name}))
    stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "template-stage", template_id: template.id, approval_type: "success"}))

    jobs =
      for i <- 1..job_count do
        job_name = "tpl-job-#{i}"
        job = Repo.insert!(%Job{} |> Job.changeset(%{name: job_name, stage_id: stage.id, resources: []}))
        Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: [job_name], job_id: job.id}))
        job
      end

    pipeline = insert_pipeline(pipeline_name, template_id: template.id)
    pipeline = Repo.preload(pipeline, [:materials, :template, stages: [jobs: :tasks]])
    {pipeline, %{template: template |> Repo.preload(stages: [jobs: :tasks]), stage: stage, jobs: jobs}}
  end

  @doc """
  Inserts a pipeline with two stages: stage1 (auto/success) and stage2 (manual).
  Also creates a git material. Used for manual gate tests.
  Returns `{pipeline, stage1, stage2}`.
  """
  def insert_pipeline_with_two_stages(name, opts \\ []) do
    material = Repo.insert!(%Material{} |> Material.changeset(%{
      type: "git", url: "https://github.com/test/#{name}.git", branch: "main", name: "#{name}-mat"
    }))

    pipeline = insert_pipeline(name, lock_behavior: Keyword.get(opts, :lock_behavior, "lockOnFailure"))
    {:ok, _} = ExGoCD.Pipelines.add_material_to_pipeline(pipeline, material)
    pipeline = Repo.preload(pipeline, :materials)

    stage1 = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "stage1", pipeline_id: pipeline.id, approval_type: "success", order_id: 1}))
    job1 = Repo.insert!(%Job{} |> Job.changeset(%{name: "job1", stage_id: stage1.id}))
    Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["1"], job_id: job1.id}))

    stage2 = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "stage2", pipeline_id: pipeline.id, approval_type: "manual", order_id: 2}))
    job2 = Repo.insert!(%Job{} |> Job.changeset(%{name: "job2", stage_id: stage2.id}))
    Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["2"], job_id: job2.id}))

    {pipeline, stage1, stage2}
  end

  @doc """
  Inserts a pipeline with a git material, one stage, one job, and one exec task.
  Returns `{pipeline, stage, job}`.
  """
  def insert_pipeline_with_job_and_material(name) do
    material = Repo.insert!(%Material{} |> Material.changeset(%{
      type: "git", url: "https://github.com/test/#{name}.git", branch: "main", name: "#{name}-mat"
    }))

    pipeline = insert_pipeline(name)

    {:ok, _} = ExGoCD.Pipelines.add_material_to_pipeline(pipeline, material)
    pipeline = Repo.preload(pipeline, :materials)

    stage = Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id, approval_type: "success"}))
    job = Repo.insert!(%Job{} |> Job.changeset(%{name: "job-1", stage_id: stage.id, resources: []}))
    Repo.insert!(%Task{} |> Task.changeset(%{type: "exec", command: "echo", arguments: ["hi"], job_id: job.id}))

    {pipeline, stage, job}
  end

  # ═══════════════════════════════════════════════════════════════════
  # Stage config inserters
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Inserts a stage config record (not an instance).
  """
  def insert_stage(pipeline_id, name, opts \\ []) do
    Repo.insert!(%Stage{} |> Stage.changeset(%{
      name: name,
      pipeline_id: pipeline_id,
      approval_type: Keyword.get(opts, :approval_type, "success"),
      order_id: Keyword.get(opts, :order_id),
      template_id: Keyword.get(opts, :template_id)
    }))
  end

  # ═══════════════════════════════════════════════════════════════════
  # Instance inserters (pipeline runs, stage runs, job runs)
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Inserts a PipelineInstance. Accepts either a Pipeline struct or a pipeline_id integer.
  """
  def insert_pipeline_instance(pipeline_or_id, counter_or_attrs) when is_integer(pipeline_or_id) do
    counter = counter_or_attrs
    label = Keyword.get(counter_or_attrs, :label, to_string(counter_or_attrs))
    Repo.insert!(%PipelineInstance{
      pipeline_id: pipeline_or_id,
      counter: counter,
      label: label,
      natural_order: counter * 1.0,
      build_cause: %{"triggerMessage" => "test trigger"}
    })
  end

  def insert_pipeline_instance(pipeline, counter) do
    Repo.insert!(%PipelineInstance{
      pipeline_id: pipeline.id,
      counter: counter,
      label: "#{pipeline.name}/#{counter}",
      natural_order: counter * 1.0,
      build_cause: %{}
    })
  end

  @doc """
  Inserts a PipelineInstance by pipeline name (looks up the pipeline).
  Used by analytics tests that need specific inserted_at timestamps.
  """
  def insert_pipeline_instance_by_name(pipeline_name, counter, inserted_at) do
    pipeline = Repo.get_by!(Pipeline, name: pipeline_name)
    Repo.insert!(%PipelineInstance{
      counter: counter,
      label: to_string(counter),
      natural_order: counter * 1.0,
      build_cause: %{"approver" => "test"},
      pipeline_id: pipeline.id,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end

  @doc """
  Inserts a StageInstance with flexible options.

  ## Options
    - `:counter` — defaults to 1
    - `:state` — defaults to `"Building"`
    - `:result` — defaults to `"Passed"`
    - `:created_time` — defaults to `DateTime.utc_now() |> DateTime.truncate(:second)`
    - `:completed_at` — optional
    - `:latest_run` — defaults to `true`
    - `:artifacts_deleted` — defaults to `false`
    - `:order_id` — defaults to 1
  """
  def insert_stage_instance(pipeline_instance_id, name, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    created = Keyword.get(opts, :created_time, now)
    completed = Keyword.get(opts, :completed_at)
    state = Keyword.get(opts, :state, "Building")
    result = Keyword.get(opts, :result, state == "Building" && "Unknown" || "Passed")

    Repo.insert!(%StageInstance{} |> StageInstance.changeset(%{
      pipeline_instance_id: pipeline_instance_id,
      name: name,
      counter: Keyword.get(opts, :counter, 1),
      order_id: Keyword.get(opts, :order_id, 1),
      state: state,
      result: result,
      approval_type: "success",
      created_time: created,
      completed_at: completed,
      latest_run: Keyword.get(opts, :latest_run, true),
      artifacts_deleted: Keyword.get(opts, :artifacts_deleted, false)
    }))
  end

  @doc """
  Inserts a completed JobInstance (assigned, completed, Passed).
  """
  def insert_job_instance(stage_instance_id, name, scheduled_at, assigned_at) do
    Repo.insert!(%JobInstance{
      name: name,
      state: "Completed",
      result: "Passed",
      scheduled_at: DateTime.to_naive(scheduled_at),
      assigned_at: DateTime.to_naive(assigned_at),
      completed_at: DateTime.to_naive(DateTime.add(assigned_at, 60, :second)),
      stage_instance_id: stage_instance_id,
      inserted_at: scheduled_at,
      updated_at: assigned_at
    })
  end

  @doc """
  Inserts a Scheduled (unassigned) JobInstance.
  """
  def insert_job_instance_unassigned(stage_instance_id, name, scheduled_at) do
    Repo.insert!(%JobInstance{
      name: name,
      state: "Scheduled",
      result: "Unknown",
      scheduled_at: DateTime.to_naive(scheduled_at),
      assigned_at: nil,
      completed_at: nil,
      stage_instance_id: stage_instance_id,
      inserted_at: scheduled_at,
      updated_at: scheduled_at
    })
  end

  # ═══════════════════════════════════════════════════════════════════
  # Material / dependency helpers
  # ═══════════════════════════════════════════════════════════════════

  @doc """
  Inserts a Material record and associates it with the pipeline.
  Returns the material.
  """
  def insert_material(pipeline, type, url) do
    mat = Repo.insert!(%Material{type: type, url: url})
    {:ok, _} = ExGoCD.Pipelines.add_material_to_pipeline(pipeline, mat)
    mat
  end

  @doc """
  Inserts a Modification for a material.
  """
  def insert_modification(material, revision) do
    Repo.insert!(%Modification{
      material_id: material.id,
      revision: revision,
      committer_name: "test",
      committer_email: "test@example.com",
      comment: "comment",
      modified_time: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @doc """
  Inserts a PipelineMaterialRevision.
  """
  def insert_pmr(pipeline_instance_id, material_id, modification_id, parent_pi_id, revision) do
    Repo.insert!(%PipelineMaterialRevision{
      pipeline_instance_id: pipeline_instance_id,
      material_id: material_id,
      modification_id: modification_id,
      parent_pipeline_instance_id: parent_pi_id,
      revision: revision
    })
  end
end
