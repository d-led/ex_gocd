defmodule ExGoCDWeb.AnalyticsLiveTest do
  use ExGoCDWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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
end
