defmodule ExGoCD.Materials.PollerTest do
  @moduledoc """
  Behavior-driven tests for the background SCM Poller.
  """
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Materials.Poller
  alias ExGoCD.Pipelines.{Job, Material, Pipeline, Stage, Task, Modification, PipelineInstance}
  alias ExGoCD.Repo
  alias ExGoCD.Scheduler

  setup do
    pid = Process.whereis(ExGoCD.Scheduler)
    if pid do
      Ecto.Adapters.SQL.Sandbox.allow(ExGoCD.Repo, self(), pid)
    end
    Scheduler.clear_queue()

    # Clean up before each test
    Repo.delete_all(Modification)
    Repo.delete_all(PipelineInstance)
    Repo.delete_all(Pipeline)
    Repo.delete_all(Material)

    # Seed material and pipeline configs
    material = Repo.insert!(%Material{
      type: "git",
      url: "https://github.com/gocd/gocd-git-repo.git",
      branch: "master",
      auto_update: true
    })

    pipeline = Repo.insert!(%Pipeline{
      name: "git-triggered-pipeline",
      group: "default"
    })

    # Join pipeline and material
    Repo.insert_all("pipelines_materials", [%{pipeline_id: pipeline.id, material_id: material.id}])

    # Add stage and job configurations
    stage = Repo.insert!(%Stage{name: "build-stage", pipeline_id: pipeline.id})
    job = Repo.insert!(%Job{name: "compile-job", stage_id: stage.id})
    Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["building..."], job_id: job.id})

    # Clear mock configuration revision
    Application.delete_env(:ex_gocd, :mock_git_revision)

    {:ok, material: material, pipeline: pipeline}
  end

  describe "materials polling and pipeline triggering" do
    test "polls a git material for the first time, saves modification, and triggers pipeline", %{
      material: material,
      pipeline: pipeline
    } do
      # Set mock revision
      sha = "c0ffee1111111111111111111111111111111111"
      Application.put_env(:ex_gocd, :mock_git_revision, sha)

      n0 = Scheduler.pending_count()

      # Trigger manual poll
      assert {:ok, results} = Poller.poll_now()
      assert [{:new_commit, mat_id, revision, triggered}] = results
      assert mat_id == material.id
      assert revision == sha
      assert triggered == [{pipeline.name, :triggered, 1}]

      # Verify modification is stored in database
      [mod] = Repo.all(Modification)
      assert mod.material_id == material.id
      assert mod.revision == sha
      assert mod.committer_name == "Mock Committer"

      # Verify pipeline run instance is created with counter 1
      [instance] = Repo.all(PipelineInstance)
      assert instance.pipeline_id == pipeline.id
      assert instance.counter == 1

      # Verify job was enqueued in scheduler
      assert Scheduler.pending_count() == n0 + 1
    end

    test "does not trigger or save modification if revision is unchanged", %{
      material: material,
      pipeline: _pipeline
    } do
      sha = "c0ffee2222222222222222222222222222222222"
      Application.put_env(:ex_gocd, :mock_git_revision, sha)

      # First poll (triggers)
      assert {:ok, [{:new_commit, _, _, _}]} = Poller.poll_now()
      assert Repo.aggregate(Modification, :count, :id) == 1
      assert Repo.aggregate(PipelineInstance, :count, :id) == 1

      # Second poll with same revision (no changes)
      assert {:ok, [{:no_change, mat_id}]} = Poller.poll_now()
      assert mat_id == material.id

      # Counts should remain at 1
      assert Repo.aggregate(Modification, :count, :id) == 1
      assert Repo.aggregate(PipelineInstance, :count, :id) == 1
    end

    test "triggers a second pipeline run when a different revision is detected", %{
      material: _material,
      pipeline: pipeline
    } do
      sha_1 = "c0ffee3333333333333333333333333333333333"
      Application.put_env(:ex_gocd, :mock_git_revision, sha_1)
      assert {:ok, [{:new_commit, _, _, _}]} = Poller.poll_now()

      # Verify first run
      [instance_1] = Repo.all(from pi in PipelineInstance, where: pi.counter == 1)
      assert instance_1.pipeline_id == pipeline.id

      # Different commit detected
      sha_2 = "c0ffee4444444444444444444444444444444444"
      Application.put_env(:ex_gocd, :mock_git_revision, sha_2)
      assert {:ok, [{:new_commit, _, _, triggered}]} = Poller.poll_now()
      assert triggered == [{pipeline.name, :triggered, 2}]

      # Verify second run is created
      [instance_2] = Repo.all(from pi in PipelineInstance, where: pi.counter == 2)
      assert instance_2.pipeline_id == pipeline.id
      assert Repo.aggregate(Modification, :count, :id) == 2
    end
  end
end
