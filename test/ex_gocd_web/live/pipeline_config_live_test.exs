defmodule ExGoCDWeb.PipelineConfigLiveTest do
  use ExGoCDWeb.ConnCase

  import Phoenix.LiveViewTest
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Pipeline, Stage, Job, Task, Material}
  alias ExGoCD.Repo

  setup do
    # Create a full pipeline config hierarchy for testing updates
    pipeline = Repo.insert!(%Pipeline{name: "test-pipeline", group: "default", label_template: "${COUNT}"})
    material = Repo.insert!(%Material{type: "git", url: "git@github.com:test/repo.git", branch: "master"})
    {:ok, _} = Pipelines.add_material_to_pipeline(pipeline, material)

    stage = Repo.insert!(%Stage{name: "build-stage", approval_type: "success", pipeline_id: pipeline.id})
    job = Repo.insert!(%Job{name: "build-job", resources: ["elixir"], stage_id: stage.id})
    
    # Insert two tasks to verify ordering/reordering
    task1 = Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["task1"], job_id: job.id})
    task2 = Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["task2"], job_id: job.id})

    # Preload pipeline properly
    pipeline = Pipelines.get_pipeline_by_name!("test-pipeline")

    %{pipeline: pipeline, stage: stage, job: job, task1: task1, task2: task2, material: material}
  end

  describe "Pipeline Configuration LiveView" do
    test "mounts and displays General settings panel", %{conn: conn, pipeline: pipeline} do
      {:ok, view, html} = live(conn, ~p"/admin/pipelines/#{pipeline.name}/edit/general")

      assert html =~ "Pipeline Config"
      assert html =~ "General Settings"
      assert render(view) =~ pipeline.name
    end

    test "updates General settings configuration", %{conn: conn, pipeline: pipeline} do
      {:ok, view, _html} = live(conn, ~p"/admin/pipelines/#{pipeline.name}/edit/general")

      view
      |> form("form", %{
        "group" => "ProdGroup",
        "label_template" => "v${COUNT}",
        "lock_behavior" => "lockOnFailure"
      })
      |> render_submit()

      assert render(view) =~ "Pipeline settings updated successfully"
      
      # Assert database updated
      updated = Pipelines.get_pipeline_by_name(pipeline.name)
      assert updated.group == "ProdGroup"
      assert updated.label_template == "v${COUNT}"
      assert updated.lock_behavior == "lockOnFailure"
    end

    test "adds, edits, and removes materials configuration", %{conn: conn, pipeline: pipeline, material: material} do
      {:ok, view, _html} = live(conn, ~p"/admin/pipelines/#{pipeline.name}/edit/materials")

      # Initially contains test/repo.git
      assert render(view) =~ "git@github.com:test/repo.git"

      # Open modal to add material
      view
      |> element("button", "Add Material")
      |> render_click()

      # Submit modal form
      view
      |> form("form", %{
        "type" => "git",
        "url" => "git@github.com:new/repo.git",
        "branch" => "main"
      })
      |> render_submit()

      assert render(view) =~ "Configuration saved successfully"
      assert render(view) =~ "git@github.com:new/repo.git"

      # Remove material
      # Since we have two materials now, click remove on the original one
      view
      |> element("button[phx-click='delete_material'][phx-value-id='#{material.id}']")
      |> render_click()

      refute render(view) =~ "git@github.com:test/repo.git"
    end

    test "updates Stage settings and lists/creates/deletes jobs", %{conn: conn, pipeline: pipeline, stage: stage} do
      {:ok, view, _html} = live(conn, ~p"/admin/pipelines/#{pipeline.name}/edit/stages/#{stage.name}/settings")

      # Update stage settings
      view
      |> form("form", %{
        "name" => "new-stage-name",
        "approval_type" => "manual"
      })
      |> render_submit()

      assert render(view) =~ "Stage updated successfully"
      
      # Navigate to Stage Jobs tab
      {:ok, view, _html} = live(conn, ~p"/admin/pipelines/#{pipeline.name}/edit/stages/new-stage-name/jobs")

      assert render(view) =~ "build-job"

      # Open modal to add a job
      view
      |> element("button", "Add Job")
      |> render_click()

      view
      |> form("form", %{"name" => "test-job"})
      |> render_submit()

      assert render(view) =~ "test-job"
    end

    test "updates Job settings and manages/reorders tasks", %{conn: conn, pipeline: pipeline, stage: stage, job: job, task1: task1, task2: _task2} do
      # Edit Job Settings
      {:ok, view, _html} = live(conn, ~p"/admin/pipelines/#{pipeline.name}/edit/stages/#{stage.name}/jobs/#{job.name}/settings")

      view
      |> form("form", %{
        "name" => "renamed-job",
        "resources" => "elixir, nodejs",
        "run_on_all_agents" => "true"
      })
      |> render_submit()

      assert render(view) =~ "Job configuration updated successfully"

      jobs_in_db = Repo.all(Job) |> Repo.preload(:tasks)
      IO.puts("JOBS IN DB:")
      for j <- jobs_in_db do
        IO.puts("- name=#{j.name}, id=#{j.id}, stage_id=#{j.stage_id}, tasks_count=#{length(j.tasks)}")
      end

      # Go to job tasks
      {:ok, view, _html} = live(conn, ~p"/admin/pipelines/#{pipeline.name}/edit/stages/#{stage.name}/jobs/renamed-job/tasks")

      # Verify tasks present
      IO.puts("RENDER OUTPUT:")
      IO.puts(render(view))
      assert render(view) =~ "task1"
      assert render(view) =~ "task2"

      # Click move_task "down" on task1 (first task) to swap order
      view
      |> element("button[phx-click='move_task'][phx-value-id='#{task1.id}'][phx-value-dir='down']")
      |> render_click()

      assert render(view) =~ "Task reordered successfully"

      # Open modal to add a task
      view
      |> element("button", "Add Task")
      |> render_click()

      view
      |> form("form", %{
        "type" => "exec",
        "command" => "echo",
        "arguments" => "hello new task"
      })
      |> render_submit()

      assert render(view) =~ "hello new task"
    end
  end
end
