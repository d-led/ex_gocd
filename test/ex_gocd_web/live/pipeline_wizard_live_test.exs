defmodule ExGoCDWeb.PipelineWizardLiveTest do
  use ExGoCDWeb.ConnCase

  import Phoenix.LiveViewTest
  alias ExGoCD.Pipelines

  describe "Pipeline Wizard LiveView" do
    test "mounts and displays Step 1", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/pipelines/new")

      assert html =~ "Add a New Pipeline"
      assert html =~ "Step 1: Basic Settings"
      assert render(view) =~ "Pipeline Name"
    end

    test "navigates through steps and saves new pipeline config to DB", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/pipelines/new")

      # Step 1: Submit name & group
      # Missing inputs should trigger validation error on change or submit
      assert view
             |> form("form", %{"name" => "", "group" => ""})
             |> render_change() =~ "Pipeline Name is required"

      # Enter valid basic details
      view
      |> form("form", %{"name" => "auto-build-pipe", "group" => "DeployGroup"})
      |> render_submit()

      # Now we should be on Step 2
      assert render(view) =~ "Step 2: Material"
      assert render(view) =~ "Repository URL"

      # Step 2: Test connection check
      view
      |> element("button", "Check Connection")
      |> render_click()

      # Simulate check completion response
      send(view.pid, :complete_connection_check)

      # Submit repository details
      view
      |> form("form", %{
        "material_type" => "git",
        "material_url" => "git@github.com:myorg/repo.git",
        "material_branch" => "main"
      })
      |> render_submit()

      # Now we should be on Step 3
      assert render(view) =~ "Step 3: Stage Details"
      assert render(view) =~ "Stage Trigger Type"

      # Step 3: Submit stage details
      view
      |> form("form", %{
        "stage_name" => "compile-stage",
        "approval_type" => "success"
      })
      |> render_submit()

      # Now we should be on Step 4
      assert render(view) =~ "Step 4: Job and Task"
      assert render(view) =~ "Initial Build Task"

      # Step 4: Submit job/task details and finish
      view
      |> form("form", %{
        "job_name" => "compile-job",
        "task_type" => "exec",
        "task_command" => "mix",
        "task_arguments" => "compile\ntest"
      })
      |> render_submit()

      # Assert DB contains the created pipeline hierarchy
      pipeline = Pipelines.get_pipeline_by_name("auto-build-pipe")
      assert pipeline
      assert pipeline.group == "DeployGroup"
      assert length(pipeline.stages) == 1

      [stage] = pipeline.stages
      assert stage.name == "compile-stage"
      assert stage.approval_type == "success"
      assert length(stage.jobs) == 1

      [job] = stage.jobs
      assert job.name == "compile-job"
      assert length(job.tasks) == 1

      [task] = job.tasks
      assert task.type == "exec"
      assert task.command == "mix"
      assert task.arguments == ["compile", "test"]

      [material] = pipeline.materials
      assert material.type == "git"
      assert material.url == "git@github.com:myorg/repo.git"
      assert material.branch == "main"
    end
  end
end
