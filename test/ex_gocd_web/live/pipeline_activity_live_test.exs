defmodule ExGoCDWeb.PipelineActivityLiveTest do
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

  describe "Pipeline Activity rendering" do
    test "renders history list for a valid pipeline", %{conn: conn} do
      # Given a valid pipeline activity route
      {:ok, _view, html} = live(conn, ~p"/pipeline/activity/build-linux")

      # Then it renders breadcrumbs and headers
      assert html =~ "Pipelines"
      assert html =~ "build-linux"
      assert html =~ "History"

      # And it renders mock pipeline run counter labels
      assert html =~ "145"
      assert html =~ "144"

      # And SCM revision details are rendered
      assert html =~ "upgrade actions and fix compilation warnings"
      assert html =~ "add test suite support"

      # And stage names are rendered
      assert html =~ "compile"
      assert html =~ "test"
      assert html =~ "package"
    end

    test "redirects to pipelines dashboard on non-existent pipeline name", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/pipelines"}}} =
               live(conn, ~p"/pipeline/activity/nonexistent-pipeline")
    end
  end

  describe "Embedded stats bar" do
    test "shows stats bar with pass rate, MTTR, avg build/wait when DB data exists", %{conn: conn} do
      # Given a pipeline with completed runs in the database
      {_pipeline, stage, [job]} = insert_pipeline_with_jobs("stats-pipeline", 1)

      pi1 = insert_pipeline_instance_by_name("stats-pipeline", 1, @now)
      si1 = insert_stage_instance(pi1.id, stage.name, created_time: @now)
      # Passed run: assigned 60s after, completed 120s after
      insert_job_instance(si1.id, job.name, @now, DateTime.add(@now, 120, :second))

      pi2 =
        insert_pipeline_instance_by_name(
          "stats-pipeline",
          2,
          DateTime.add(@now, 300, :second)
        )

      si2 =
        insert_stage_instance(pi2.id, stage.name, created_time: DateTime.add(@now, 300, :second))

      # Failed run: assigned 30s after, completed 60s after
      ji2 =
        insert_job_instance(
          si2.id,
          job.name,
          DateTime.add(@now, 300, :second),
          DateTime.add(@now, 360, :second)
        )

      ExGoCD.Pipelines.complete_job_instance(ji2.id, "Failed")

      # When viewing the pipeline activity page
      {:ok, _view, html} = live(conn, ~p"/pipeline/activity/stats-pipeline")

      # Then the stats bar renders with analytics data
      assert html =~ "stats-bar"
      assert html =~ "Pass Rate"
      assert html =~ "MTTR"
      assert html =~ "Avg Build"
      assert html =~ "Avg Wait"
    end
  end
end
