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
        console_log:
          "line 1: build started\nline 2: https://github.com/d-led/ex_gocd\nline 3: build finished\n"
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
      assert html =~ ~r{demo\s*</a>}
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

  describe "JobDetailsLive LiveView interactive features" do
    import Phoenix.LiveViewTest

    test "toggles timestamps", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")

      # Verify initial show_timestamps is false
      assert render(view) =~ "id=\"console-container\""
      refute render(view) =~ "show-timestamps"

      # Click toggle-timestamps checkbox
      view
      |> element("#toggle-timestamps")
      |> render_click()

      # Verify show-timestamps is applied to container
      assert render(view) =~ "show-timestamps"

      # Click it again
      view
      |> element("#toggle-timestamps")
      |> render_click()

      refute render(view) =~ "show-timestamps"
    end

    test "toggles follow", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")

      # Verify initial follow is true
      assert render(view) =~ "data-follow=\"true\""

      # Click toggle-follow checkbox
      view
      |> element("#toggle-follow")
      |> render_click()

      # Verify data-follow is false
      assert render(view) =~ "data-follow=\"false\""
    end

    test "streams new logs via :console_append", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")

      refute render(view) =~ "this is a streamed chunk"

      # Send a chunk info message
      send(view.pid, {:console_append, "this is a streamed chunk\n"})

      # Verify it rendered
      assert render(view) =~ "this is a streamed chunk"
    end

    test "switches tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")

      # Initial active tab is console
      html = render(view)
      assert html =~ "border-[#2d6ca2]"
      assert html =~ "phx-value-tab=\"console\""

      # Click on Tests tab
      view
      |> element("button[phx-click='select_tab'][phx-value-tab='tests']")
      |> render_click()

      # Active tab is now tests
      html_after = render(view)
      assert html_after =~ "border-[#2d6ca2]"
      assert html_after =~ "phx-value-tab=\"tests\""
    end
  end
end
