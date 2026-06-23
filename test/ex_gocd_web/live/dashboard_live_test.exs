defmodule ExGoCDWeb.DashboardLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "renders dashboard with default state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Search pipelines"
      assert html =~ "Group pipelines by:"
      assert html =~ "Pipeline Dashboard"
    end

    test "initializes with default assigns", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert page_title(view) =~ "Pipelines"
      assert has_element?(view, "[role='search']")
      assert has_element?(view, "[role='combobox']")
    end

    test "dropdown is closed by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, ".c-dropdown.open")
      assert has_element?(view, "[aria-expanded='false']")
    end

    test "default grouping is Environment", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Environment"
      assert has_element?(view, "[aria-selected='true']", "Environment")
    end
  end

  describe "search functionality" do
    test "updates search text on input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#pipeline-search-form", %{"value" => "my-pipeline"})
      |> render_change()

      assert render(view) =~ ~s(value="my-pipeline")
    end

    test "debounces search input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Input has phx-debounce="300" attribute
      assert has_element?(view, "#pipeline-search[phx-debounce='300']")
    end

    test "search field has proper accessibility attributes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#pipeline-search[aria-label='Search pipelines']")
      assert has_element?(view, "label[for='pipeline-search']", "Search pipelines")
      assert has_element?(view, "#pipeline-search[autocomplete='off']")
    end
  end

  describe "grouping dropdown" do
    test "toggles dropdown open state on click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, ".c-dropdown.open")

      view
      |> element(".c-dropdown-head")
      |> render_click()

      assert has_element?(view, ".c-dropdown.open")
      assert has_element?(view, "[aria-expanded='true']")
    end

    test "closes dropdown on second click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open dropdown
      view
      |> element(".c-dropdown-head")
      |> render_click()

      assert has_element?(view, ".c-dropdown.open")

      # Close dropdown
      view
      |> element(".c-dropdown-head")
      |> render_click()

      refute has_element?(view, ".c-dropdown.open")
      assert has_element?(view, "[aria-expanded='false']")
    end

    test "selects Environment grouping scheme", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open dropdown and select Pipeline Group first
      view
      |> element(".c-dropdown-head")
      |> render_click()

      view
      |> element(".c-dropdown-item", "Pipeline Group")
      |> render_click()

      assert render(view) =~ "Pipeline Group"

      # Now select Environment
      view
      |> element(".c-dropdown-head")
      |> render_click()

      view
      |> element(".c-dropdown-item", "Environment")
      |> render_click()

      assert render(view) =~ "Environment"
      refute has_element?(view, ".c-dropdown.open")
    end

    test "selects Pipeline Group grouping scheme", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element(".c-dropdown-head")
      |> render_click()

      view
      |> element(".c-dropdown-item", "Pipeline Group")
      |> render_click()

      assert render(view) =~ "Pipeline Group"
      assert has_element?(view, "[aria-selected='true']", "Pipeline Group")
      refute has_element?(view, ".c-dropdown.open")
    end

    test "closes dropdown when clicking away", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Open dropdown
      view
      |> element(".c-dropdown-head")
      |> render_click()

      assert has_element?(view, ".c-dropdown.open")

      # This simulates clicking outside the dropdown
      # phx-click-away="close_dropdown" should trigger
      view
      |> render_hook("close_dropdown", %{})

      refute has_element?(view, ".c-dropdown.open")
    end

    test "dropdown has proper ARIA attributes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "[role='combobox'][aria-haspopup='listbox']")
      assert has_element?(view, ".c-dropdown-body[role='listbox']")
      assert has_element?(view, ".c-dropdown-item[role='option']")
      assert has_element?(view, "label#grouping-label", "Group pipelines by:")
    end

    test "dropdown items are keyboard accessible", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ".c-dropdown-head[tabindex='0']")
      assert has_element?(view, ".c-dropdown-item[tabindex='0']")
    end

    test "Pipeline Group grouping shows distinct group sections with DB data", %{conn: conn} do
      # Create pipelines with different groups
      alias ExGoCD.Pipelines.Pipeline
      alias ExGoCD.Repo

      Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "grp-frontend", group: "frontend"}))
      Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "grp-backend", group: "backend"}))

      {:ok, view, _html} = live(conn, ~p"/")

      # Select Pipeline Group
      view |> element(".c-dropdown-head") |> render_click()
      view |> element(".c-dropdown-item", "Pipeline Group") |> render_click()

      html = render(view)
      assert html =~ "frontend"
      assert html =~ "backend"
      refute html =~ "Default"
    end

    test "Environment grouping shows all pipelines under one section when no environments exist", %{conn: conn} do
      alias ExGoCD.Pipelines.Pipeline
      alias ExGoCD.Repo

      Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "env-frontend", group: "frontend"}))
      Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "env-backend", group: "backend"}))

      {:ok, view, _html} = live(conn, ~p"/")

      # Select Environment
      view |> element(".c-dropdown-head") |> render_click()
      view |> element(".c-dropdown-item", "Environment") |> render_click()

      html = render(view)
      # Without environments, all pipelines should appear together (not grouped by pipeline group)
      assert html =~ "env-frontend"
      assert html =~ "env-backend"
    end

    test "switching between Pipeline Group and Environment changes grouping output", %{conn: conn} do
      alias ExGoCD.Pipelines.Pipeline
      alias ExGoCD.Repo

      Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "switch-frontend", group: "frontend"}))
      Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "switch-backend", group: "backend"}))

      {:ok, view, _html} = live(conn, ~p"/")

      # Pipeline Group — should show separate section headers
      view |> element(".c-dropdown-head") |> render_click()
      view |> element(".c-dropdown-item", "Pipeline Group") |> render_click()
      pg_html = render(view)

      # Environment — should show different structure
      view |> element(".c-dropdown-head") |> render_click()
      view |> element(".c-dropdown-item", "Environment") |> render_click()
      env_html = render(view)

      # The two modes should produce DIFFERENT HTML (not identical)
      assert pg_html != env_html,
        "Pipeline Group and Environment grouping must produce distinct results"
    end

    test "selecting grouping persists in URL via group_by param", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element(".c-dropdown-head") |> render_click()
      view |> element(".c-dropdown-item", "Pipeline Group") |> render_click()

      assert_patched(view, ~p"/pipelines?group_by=pipeline_group")
    end

    test "loading URL with group_by=pipeline_group sets correct grouping", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/pipelines?group_by=pipeline_group")

      assert html =~ "Pipeline Group"
      assert has_element?(view, "[aria-selected='true']", "Pipeline Group")
    end

    test "loading URL with group_by=environment shows environment grouping", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/pipelines?group_by=environment")

      assert html =~ "Environment"
      assert has_element?(view, "[aria-selected='true']", "Environment")
    end

    test "loading URL without group_by defaults to environment", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/pipelines")

      assert html =~ "Environment"
      assert has_element?(view, "[aria-selected='true']", "Environment")
    end

    test "switching grouping preserves search param in URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pipelines?search=frontend")

      view |> element(".c-dropdown-head") |> render_click()
      view |> element(".c-dropdown-item", "Pipeline Group") |> render_click()

      assert_patched(view, ~p"/pipelines?group_by=pipeline_group&search=frontend")
    end
  end

  describe "accessibility" do
    test "has proper landmark roles", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "[role='main'][aria-label='Pipeline Dashboard']")
      assert has_element?(view, "[role='search'][aria-label='Pipeline filters']")
      assert has_element?(view, "#flash-group[aria-live='polite']")
    end

    test "has descriptive labels for screen readers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ".sr-only", "Search pipelines")
      assert has_element?(view, "label#grouping-label", "Group pipelines by:")
    end

    test "dropdown button has accessible label", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "[aria-label='Group by Environment']")
    end
  end

  describe "pipelines display" do
    test "displays mock pipelines from ExGoCD.MockData", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      # Check for pipeline groups
      assert html =~ "dashboard-group"
      assert has_element?(view, ".dashboard-group")
      assert has_element?(view, ".pipeline")
    end
  end

  describe "responsive design" do
    test "renders dashboard container with proper structure", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ".dashboard")
      assert has_element?(view, ".dashboard-modifiers")
      assert has_element?(view, ".dashboard-group")
    end

    test "search input has proper responsive classes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ".pipeline-search_dashboard")
      assert has_element?(view, "#pipeline-search")
    end

    test "pipeline groups render in responsive grid layout", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ".dashboard-group_items")
      assert has_element?(view, ".dashboard-group_pipeline")
    end

    test "pipeline cards have responsive structure", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ".pipeline_header")
      assert has_element?(view, ".pipeline_instances")
      assert has_element?(view, ".pipeline_stages")
    end

    test "empty state message is properly centered", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Trigger search with non-existent pipeline
      view
      |> form("#pipeline-search-form", %{"value" => "nonexistent-pipeline-xyz"})
      |> render_change()

      html = render(view)

      assert html =~ "dashboard-message"
      assert html =~ "text-center"
      assert html =~ "No matches found"
      assert html =~ "nonexistent-pipeline-xyz"
    end
  end

  describe "pipeline pause/unpause UI" do
    alias ExGoCD.Pipelines
    alias ExGoCD.Repo

    test "can open pause modal, pause a pipeline, show paused state, and unpause", %{conn: conn} do
      System.put_env("USE_MOCK_DATA", "false")
      on_exit(fn -> System.delete_env("USE_MOCK_DATA") end)

      # Seed admin user to exit open mode
      {:ok, _} = ExGoCD.Accounts.create_user(%{username: "admin", display_name: "System Administrator", roles: ["admin", "developer"], status: "Active"})

      # Insert a pipeline config in the DB
      _pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-dashboard-pause", group: "test"})

      # Log in as admin
      conn = log_in_as(conn, "admin")
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "test-dashboard-pause"

      # Verify pause button is present and not unpause
      assert has_element?(view, "button[aria-label='Pause Pipeline']")
      refute has_element?(view, "button[aria-label='Pipeline Paused']")

      # Open the pause modal
      view
      |> element("button[aria-label='Pause Pipeline']")
      |> render_click()

      # Verify the modal is open
      assert has_element?(view, "#pause-modal")
      assert render(view) =~ "Specify a reason for pausing schedule on pipeline test-dashboard-pause"

      # Submit the pause cause form
      view
      |> form("#pause-pipeline-form", %{"pause_cause" => "maintenance downtime"})
      |> render_submit()

      # Verify the pipeline is now paused
      html = render(view)
      assert html =~ "Pipeline test-dashboard-pause paused successfully."
      assert html =~ "Paused by admin (maintenance downtime)"
      assert has_element?(view, "button[aria-label='Pipeline Paused']")
      assert has_element?(view, "button[aria-label='Trigger Pipeline Disabled'].disabled")

      # Unpause the pipeline
      view
      |> element("button[aria-label='Pipeline Paused']")
      |> render_click()

      # Verify it is unpaused
      html = render(view)
      assert html =~ "Pipeline test-dashboard-pause unpaused successfully."
      refute html =~ "Paused by admin"
      assert has_element?(view, "button[aria-label='Pause Pipeline']")
      refute has_element?(view, "button[aria-label='Trigger Pipeline Disabled']")
    end

    test "viewers are blocked from pausing/unpausing", %{conn: conn} do
      System.put_env("USE_MOCK_DATA", "false")
      on_exit(fn -> System.delete_env("USE_MOCK_DATA") end)

      # Seed admin and viewer users
      {:ok, _} = ExGoCD.Accounts.create_user(%{username: "admin", display_name: "System Administrator", roles: ["admin", "developer"], status: "Active"})
      {:ok, _} = ExGoCD.Accounts.create_user(%{username: "viewer", display_name: "Guest Viewer", roles: [], status: "Active"})

      _pipeline = Repo.insert!(%Pipelines.Pipeline{name: "test-viewer-pause", group: "test"})

      # Log in as viewer
      conn = log_in_as(conn, "viewer")
      {:ok, view, _html} = live(conn, ~p"/")

      # Verify play and pause buttons are disabled visually
      assert has_element?(view, "button[aria-label='Pause Pipeline'].disabled")
      assert has_element?(view, "button[aria-label='Trigger Pipeline'].disabled")

      # Try triggering the pause event directly to ensure backend guards enforce permission
      assert render_click(view, "show_pause_modal", %{"name" => "test-viewer-pause"}) =~ "You do not have operate permissions"
    end
  end
end
