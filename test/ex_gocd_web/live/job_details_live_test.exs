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

    test "renders timestamps toggle (off by default)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")

      # Verify initial show_timestamps is false (class not on container)
      html = render(view)
      assert html =~ "id=\"console-container\""
      refute html =~ ~s(class="console-log bg-gray-950[^"]*show-timestamps)
      assert html =~ "id=\"toggle-timestamps\""
    end

    test "renders follow toggle (on by default)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")

      # Verify initial follow is true
      html = render(view)
      assert html =~ "data-follow=\"true\""
      assert html =~ "id=\"toggle-follow\""
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

    test "renders line wrap toggle (on by default)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")

      # Initially wrap is enabled (checkbox checked, container has no no-wrap class)
      html = render(view)
      assert html =~ "id=\"toggle-wrap\""
      assert html =~ "checked"
      refute html =~ ~s(class="console-log bg-gray-950[^"]*no-wrap)
    end
  end

  describe "fold parsing" do
    setup do
      {:ok, _run} =
        %AgentJobRun{}
        |> AgentJobRun.changeset(%{
          build_id: "test-fold-001",
          pipeline_name: "demo",
          pipeline_counter: 2,
          stage_name: "build",
          stage_counter: 1,
          job_name: "default",
          state: "Completed",
          result: "Passed",
          agent_uuid: "550e8400-e29b-41d4-a716-446655440000",
          console_log:
            "##[fold]Setup\e[0m\ninstalling deps\n##[fold]Nested Section\nnested content\n##[endfold]\nmore setup\n##[endfold]\nfinal line\n"
        })
        |> Repo.insert()

      :ok
    end

    test "renders fold-start headers with fold names", %{conn: conn} do
      conn = get(conn, ~p"/go/tab/build/detail/demo/2/build/1/default")
      html = html_response(conn, 200)

      assert html =~ "Setup"
      assert html =~ "Nested Section"
    end

    test "fold headers have fold-start class", %{conn: conn} do
      conn = get(conn, ~p"/go/tab/build/detail/demo/2/build/1/default")
      html = html_response(conn, 200)

      assert html =~ "fold-start"
    end

    test "ANSI codes are stripped from fold names", %{conn: conn} do
      conn = get(conn, ~p"/go/tab/build/detail/demo/2/build/1/default")
      html = html_response(conn, 200)

      refute html =~ ~r{\\e\[0m}
    end
  end

  describe "stream limit" do
    setup do
      lines = for i <- 1..1200, do: "line #{i}"
      log = Enum.join(lines, "\n")

      {:ok, _run} =
        %AgentJobRun{}
        |> AgentJobRun.changeset(%{
          build_id: "test-limit-001",
          pipeline_name: "demo",
          pipeline_counter: 3,
          stage_name: "build",
          stage_counter: 1,
          job_name: "default",
          state: "Completed",
          result: "Passed",
          agent_uuid: "550e8400-e29b-41d4-a716-446655440000",
          console_log: log
        })
        |> Repo.insert()

      :ok
    end

    test "shows truncation banner when line_count exceeds 1000", %{conn: conn} do
      conn = get(conn, ~p"/go/tab/build/detail/demo/3/build/1/default")
      html = html_response(conn, 200)

      assert html =~ "Showing the last 1,000 lines"
      assert html =~ "Download Full Log"
    end

    test "first lines are dropped, last lines are visible", %{conn: conn} do
      conn = get(conn, ~p"/go/tab/build/detail/demo/3/build/1/default")
      html = html_response(conn, 200)

      refute html =~ "line 1\n"
      assert html =~ "line 1200"
    end
  end

  describe "whitespace regression guard" do
    test "log-message spans have no leading whitespace in static HTML", %{conn: conn} do
      conn = get(conn, ~p"/go/tab/build/detail/demo/1/build/1/default")
      html = html_response(conn, 200)

      ~r{<span[^>]*class="log-message[^"]*"[^>]*>(.*?)</span>}s
      |> Regex.scan(html)
      |> Enum.each(fn [_, text] ->
        trimmed = String.trim(text)
        if trimmed != "" do
          refute String.starts_with?(text, "\n"),
            "log-message starts with newline: #{inspect(String.slice(text, 0, 40))}"
          refute String.starts_with?(text, " "),
            "log-message starts with space: #{inspect(String.slice(text, 0, 40))}"
        end
      end)
    end
  end

  describe "CSS defense against template reformatting" do
    test "app.css contains font-size:0 defense on .log-row" do
      css_path = Path.join(File.cwd!(), "assets/css/app.css")
      css = File.read!(css_path)

      # The defense rule: .log-row { font-size: 0 } collapses whitespace text nodes
      assert css =~ ~r/\.log-row\s*\{[^}]*font-size:\s*0/
    end

    test "app.css restores font-size on .log-row children" do
      css_path = Path.join(File.cwd!(), "assets/css/app.css")
      css = File.read!(css_path)

      # Children rule: .log-row > * { font-size: 11px } restores on real elements
      assert css =~ ~r/\.log-row\s*>\s*\*\s*\{[^}]*font-size:\s*11px/
    end
  end
end
