defmodule ExGoCDWeb.AnalyticsLiveTest do
  use ExGoCDWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Pipelines

  describe "Analytics page" do
    test "opens on the global tab with nothing to report yet", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/analytics")

      assert has_element?(view, "button[phx-value-tab='global'][aria-selected='true']")
      assert html =~ "Top Pipelines by Wait Time (7d avg)"
      assert html =~ "No data yet"
    end

    test "switches to the pipelines tab and lists the pipelines", %{conn: conn} do
      {:ok, _pipeline} = Pipelines.create_pipeline(%{name: "deploy", group: "test"})

      {:ok, view, _html} = live(conn, ~p"/analytics")

      view |> element("button", "Pipelines") |> render_click()

      assert_patch(view, ~p"/analytics/pipelines")
      assert render(view) =~ "deploy"
    end

    test "switches to the VSM trends tab, which needs a pipeline chosen first", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analytics")

      view |> element("button", "VSM Trends") |> render_click()

      assert_patch(view, ~p"/analytics/vsm")
      assert render(view) =~ "Select a pipeline from the Pipelines tab"
    end

    test "a tab the page does not know says so instead of rendering nothing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analytics/load_time")

      assert html =~ "Select a tab above."
    end
  end

  describe "the numbers on the page" do
    test "a pipeline that waited for an agent is listed with its wait", %{conn: conn} do
      run_that_waited("deploy", waited_seconds: 90)

      {:ok, view, html} = live(conn, ~p"/analytics")

      assert has_element?(view, "tr[phx-value-name='deploy']")
      assert html =~ "1.5m"
    end

    test "a pipeline's own tab shows how it has been doing", %{conn: conn} do
      run_that_waited("deploy", waited_seconds: 30)

      {:ok, _view, html} = live(conn, ~p"/analytics/pipeline_detail?pipeline=deploy")

      assert html =~ "deploy"
      assert html =~ "100.0%"
    end
  end

  defp run_that_waited(pipeline_name, opts) do
    {:ok, _pipeline} = Pipelines.create_pipeline(%{name: pipeline_name, group: "test"})
    started_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-3600, :second)

    instance = insert_pipeline_instance_by_name(pipeline_name, 1, started_at)

    stage =
      insert_stage_instance(instance.id, "build",
        state: "Completed",
        result: "Passed",
        inserted_at: started_at,
        created_time: started_at,
        completed_at: usec(DateTime.add(started_at, 60, :second))
      )

    assigned_at = DateTime.add(started_at, Keyword.fetch!(opts, :waited_seconds), :second)
    insert_job_instance(stage.id, "compile", usec(started_at), usec(assigned_at))
  end

  defp usec(time), do: DateTime.add(time, 0, :microsecond)
end
