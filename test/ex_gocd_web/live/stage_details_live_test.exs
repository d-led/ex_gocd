defmodule ExGoCDWeb.StageDetailsLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "Stage Details rendering" do
    test "renders stage run metadata and breadcrumbs", %{conn: conn} do
      # Given a valid stage details route
      {:ok, _view, html} = live(conn, ~p"/pipelines/build-linux/1/compile/1")

      # Then it renders breadcrumbs and headers
      assert html =~ "build-linux"
      assert html =~ "1"
      assert html =~ "compile"
      assert html =~ "Run Details"

      # And it renders default Jobs tab with job details
      assert html =~ "Jobs"
      assert html =~ "Job Name"
      assert html =~ "build_job"
      assert html =~ "Completed"
    end

    test "toggles active tab to Configuration", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pipelines/build-linux/1/compile/1")

      # When selecting the Configuration tab
      html =
        view
        |> element("button", "Configuration")
        |> render_click()

      # Then it renders Configuration metadata
      assert html =~ "Clean Working Directory"
      assert html =~ "Fetch Materials"
      assert html =~ "Approval Type"
    end

    test "toggles active tab to Console Log", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pipelines/build-linux/1/compile/1")

      # When selecting the Console Log tab
      html =
        view
        |> element("button", "Console Log")
        |> render_click()

      # Then it renders simulated build output
      assert html =~ "[go] Start to build pipeline"
      assert html =~ "Executing task command: mix compile"
      assert html =~ "mix test"
    end
  end
end
