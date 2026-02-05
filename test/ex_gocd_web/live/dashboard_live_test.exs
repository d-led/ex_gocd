defmodule ExGoCDWeb.DashboardLiveTest do
  use ExGoCDWeb.ConnCase

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

      assert view |> element("title") |> render() =~ "Pipelines"
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
      |> element("#pipeline-search")
      |> render_change(%{"value" => "my-pipeline"})

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
end
