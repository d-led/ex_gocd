defmodule ExGoCDWeb.GanttLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import ExGoCD.PipelinesFixtures,
    only: [
      insert_pipeline_with_jobs: 2,
      insert_pipeline_instance_by_name: 3,
      insert_stage_instance: 3
    ]

  describe "stage duration charts" do
    test "a pipeline that never finished a stage says so", %{conn: conn} do
      insert_pipeline_with_jobs("idle-pipeline", 1)

      {:ok, _view, html} = live(conn, ~p"/stage-duration/idle-pipeline")

      assert html =~ "No pipeline runs with completed stages yet."
    end

    test "each finished stage run is a point linked to that run", %{conn: conn} do
      insert_pipeline_with_jobs("timed-pipeline", 1)
      passed = insert_run("timed-pipeline", 1, ~U[2026-07-01 10:00:00.000000Z], "Passed", 30)
      failed = insert_run("timed-pipeline", 2, ~U[2026-07-01 11:00:00.000000Z], "Failed", 120)

      {:ok, view, _html} = live(conn, ~p"/stage-duration/timed-pipeline")

      assert has_element?(view, "[data-test-id='chart-stage-build']")

      html = render(view)
      assert html =~ ~s{href="/pipelines/timed-pipeline/#{passed.counter}/build/1"}
      assert html =~ ~s{href="/pipelines/timed-pipeline/#{failed.counter}/build/1"}
    end
  end

  defp insert_run(pipeline_name, counter, started_at, result, seconds) do
    instance = insert_pipeline_instance_by_name(pipeline_name, counter, started_at)

    insert_stage_instance(instance.id, "build",
      state: result,
      result: result,
      created_time: started_at,
      completed_at: DateTime.add(started_at, seconds, :second)
    )
  end
end
