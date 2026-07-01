defmodule ExGoCDWeb.StageDetailsLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import ExGoCD.PipelinesFixtures,
    only: [
      insert_pipeline_with_jobs: 2,
      insert_pipeline_instance_by_name: 3,
      insert_stage_instance: 3,
      insert_job_instance: 4
    ]

  @now ~U[2026-07-01 10:00:00.000000Z]

  describe "Stage Details rendering" do
    test "renders stage run metadata and breadcrumbs", %{conn: conn} do
      # Given a valid stage details route
      {:ok, _view, html} = live(conn, ~p"/pipelines/build-linux/1/compile/1")

      # Then it renders breadcrumbs and headers
      assert html =~ "build-linux"
      assert html =~ "1"
      assert html =~ "compile"
      assert html =~ "Run Details"

      # And it renders default Jobs tab with job details
      assert html =~ "Jobs"
      assert html =~ "Job Name"
      assert html =~ "build_job"
      assert html =~ "Completed"
    end

    test "toggles active tab to Configuration", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pipelines/build-linux/1/compile/1")

      # When selecting the Configuration tab
      html =
        view
        |> element("button", "Configuration")
        |> render_click()

      # Then it renders Configuration metadata
      assert html =~ "Clean Working Directory"
      assert html =~ "Fetch Materials"
      assert html =~ "Approval Type"
    end

    test "toggles active tab to Console Log", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pipelines/build-linux/1/compile/1")

      # When selecting the Console Log tab
      html =
        view
        |> element("button", "Console Log")
        |> render_click()

      # Then it renders simulated build output
      assert html =~ "[go] Start to build pipeline"
      assert html =~ "Executing task command: mix compile"
      assert html =~ "mix test"
    end
  end

  describe "Trends tab with summary stats" do
    test "shows pass rate, avg duration, and passed/failed summaries with DB data", %{conn: conn} do
      # Given a pipeline with completed stage runs
      {_pipeline, stage, [job]} = insert_pipeline_with_jobs("trends-pipeline", 1)

      # Run 1: passed, 120s duration
      pi1 = insert_pipeline_instance_by_name("trends-pipeline", 1, @now)
      si1 = insert_stage_instance(pi1.id, stage.name, created_time: @now)
      insert_job_instance(si1.id, job.name, @now, DateTime.add(@now, 120, :second))

      # Run 2: failed, 60s duration
      pi2 =
        insert_pipeline_instance_by_name(
          "trends-pipeline",
          2,
          DateTime.add(@now, 300, :second)
        )

      si2 =
        insert_stage_instance(pi2.id, stage.name, created_time: DateTime.add(@now, 300, :second))

      ji2 =
        insert_job_instance(
          si2.id,
          job.name,
          DateTime.add(@now, 300, :second),
          DateTime.add(@now, 360, :second)
        )

      ExGoCD.Pipelines.complete_job_instance(ji2.id, "Failed")

      # When viewing the stage details and selecting the Trends tab
      {:ok, view, _html} = live(conn, ~p"/pipelines/trends-pipeline/2/#{stage.name}/1")

      html =
        view
        |> element("button", "Trends")
        |> render_click()

      # Then summary stat cards render
      assert html =~ "Pass Rate"
      assert html =~ "Avg Duration"
      assert html =~ "Passed"

      # And the bar chart renders with individual runs
      assert html =~ "Passed"
      assert html =~ "Failed"
    end
  end
end
