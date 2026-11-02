defmodule ExGoCDWeb.API.DashboardControllerTest do
  @moduledoc """
  The dashboard API is what a GoCD dashboard reads: pipeline groups, each
  pipeline's latest run, and a status derived from that run's stages. The status
  has an order of precedence that is easy to get subtly wrong, so each case is
  stated here.
  """
  use ExGoCDWeb.ConnCase, async: true

  import ExGoCD.PipelinesFixtures

  describe "with no pipelines at all" do
    test "answers an empty dashboard", %{conn: conn} do
      body = conn |> get("/api/dashboard") |> json_response(200)

      assert body["pipeline_groups"] == []
    end
  end

  describe "a pipeline that has never run" do
    test "is reported as never run", %{conn: conn} do
      insert_pipeline("never-run", group: "team-a")

      body = conn |> get("/api/dashboard") |> json_response(200)

      assert [%{"name" => "team-a", "pipelines" => [pipeline]}] = body["pipeline_groups"]
      assert pipeline["name"] == "never-run"
      assert pipeline["latest_instance"]["status"] == "NeverRun"
      assert pipeline["latest_instance"]["counter"] == 0
    end
  end

  describe "the status of a pipeline's latest run" do
    test "is passed when every stage passed", %{conn: conn} do
      run_pipeline("all-passed", [{"build", "Passed", "Passed"}])

      assert dashboard_status_for(conn, "all-passed") == "Passed"
    end

    test "is failed when a stage failed", %{conn: conn} do
      run_pipeline("one-failed", [{"build", "Passed", "Passed"}, {"test", "Completed", "Failed"}])

      assert dashboard_status_for(conn, "one-failed") == "Failed"
    end

    test "is building while a stage is still running", %{conn: conn} do
      run_pipeline("still-running", [{"build", "Building", "Unknown"}])

      assert dashboard_status_for(conn, "still-running") == "Building"
    end

    test "is cancelled when the run was cancelled", %{conn: conn} do
      run_pipeline("given-up", [{"build", "Cancelled", "Cancelled"}])

      assert dashboard_status_for(conn, "given-up") == "Cancelled"
    end
  end

  describe "grouping" do
    test "puts pipelines of one group together", %{conn: conn} do
      insert_pipeline("first", group: "team-b")
      insert_pipeline("second", group: "team-b")
      insert_pipeline("third", group: "team-c")

      body = conn |> get("/api/dashboard") |> json_response(200)

      names_by_group = Map.new(body["pipeline_groups"], &{&1["name"], names(&1)})

      assert names_by_group["team-b"] == ["first", "second"]
      assert names_by_group["team-c"] == ["third"]
    end
  end

  defp names(group), do: group["pipelines"] |> Enum.map(& &1["name"]) |> Enum.sort()

  defp dashboard_status_for(conn, pipeline_name) do
    body = conn |> get("/api/dashboard") |> json_response(200)

    body["pipeline_groups"]
    |> Enum.flat_map(& &1["pipelines"])
    |> Enum.find(&(&1["name"] == pipeline_name))
    |> get_in(["latest_instance", "status"])
  end

  defp run_pipeline(name, stages) do
    insert_pipeline(name, group: "team-a")
    instance = insert_pipeline_instance_by_name(name, 1, DateTime.utc_now())

    Enum.each(stages, fn {stage_name, state, result} ->
      insert_stage_instance(instance.id, stage_name, state: state, result: result)
    end)
  end
end
