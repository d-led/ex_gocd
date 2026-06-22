defmodule ExGoCDWeb.JobDetailsLiveTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.Repo

  setup do
    {:ok, _run} =
      %AgentJobRun{}
      |> AgentJobRun.changeset(%{
        build_id: "test-build-001",
        pipeline_name: "demo",
        pipeline_counter: 1,
        stage_name: "build",
        stage_counter: 1,
        job_name: "default",
        state: "Completed",
        result: "Passed",
        agent_uuid: "550e8400-e29b-41d4-a716-446655440000",
        console_log: "line 1: build started\nline 2: https://github.com/d-led/ex_gocd\nline 3: build finished\n"
      })
      |> Repo.insert()

    :ok
  end

  describe "console tab" do
    test "renders console output with clickable links", %{conn: conn} do
      conn = get(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")
      html = html_response(conn, 200)
      assert html =~ "line 1: build started"
      assert html =~ "github.com/d-led/ex_gocd"
    end

    test "renders Copy button and controls", %{conn: conn} do
      conn = get(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")
      html = html_response(conn, 200)
      assert html =~ "Copy"
      assert html =~ "Timestamps"
      assert html =~ "Follow"
      assert html =~ "Filter"
    end

    test "renders breadcrumb navigation", %{conn: conn} do
      conn = get(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")
      html = html_response(conn, 200)
      assert html =~ "demo</a>"
    end

    test "shows tabs: Console, Tests, Artifacts, Materials", %{conn: conn} do
      conn = get(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")
      html = html_response(conn, 200)
      assert html =~ "Console Log"
      assert html =~ "Tests"
      assert html =~ "Artifacts"
      assert html =~ "Materials"
    end
  end
end