defmodule ExGoCDWeb.CompareLiveTest do
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

  describe "Compare LiveView rendering" do
    test "renders picker page when no counters selected", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/compare/build-linux")
      assert html =~ "Compare"
      assert html =~ "From Instance"
      assert html =~ "To Instance"
      assert html =~ "Pick any two instances"
    end

    test "shows comparison with DB pipeline data", %{conn: conn} do
      {_pipeline, stage, [job]} = insert_pipeline_with_jobs("cmp-pipeline", 1)

      pi1 = insert_pipeline_instance_by_name("cmp-pipeline", 1, @now)
      si1 = insert_stage_instance(pi1.id, stage.name, created_time: @now)
      ji1 = insert_job_instance(si1.id, job.name, @now, DateTime.add(@now, 60, :second))
      ExGoCD.Pipelines.complete_job_instance(ji1.id, "Passed")

      pi2 = insert_pipeline_instance_by_name("cmp-pipeline", 2, DateTime.add(@now, 300, :second))
      si2 = insert_stage_instance(pi2.id, stage.name, created_time: DateTime.add(@now, 300, :second))
      ji2 = insert_job_instance(si2.id, job.name, DateTime.add(@now, 300, :second), DateTime.add(@now, 360, :second))
      ExGoCD.Pipelines.complete_job_instance(ji2.id, "Passed")

      {:ok, _view, html} = live(conn, ~p"/compare/cmp-pipeline/1/with/2")

      # Should render materials and environment variables sections
      assert html =~ "Compare"
      assert html =~ "From"
      assert html =~ "To"
    end
  end
end
