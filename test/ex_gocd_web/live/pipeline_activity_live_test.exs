defmodule ExGoCDWeb.PipelineActivityLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "Pipeline Activity rendering" do
    test "renders history list for a valid pipeline", %{conn: conn} do
      # Given a valid pipeline activity route
      {:ok, _view, html} = live(conn, ~p"/pipeline/activity/build-linux")

      # Then it renders breadcrumbs and headers
      assert html =~ "Pipelines"
      assert html =~ "build-linux"
      assert html =~ "History"

      # And it renders mock pipeline run counter labels
      assert html =~ "145"
      assert html =~ "144"

      # And SCM revision details are rendered
      assert html =~ "upgrade actions and fix compilation warnings"
      assert html =~ "add test suite support"

      # And stage names are rendered
      assert html =~ "compile"
      assert html =~ "test"
      assert html =~ "package"
    end

    test "redirects to pipelines dashboard on non-existent pipeline name", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/pipelines"}}} =
               live(conn, ~p"/pipeline/activity/nonexistent-pipeline")
    end
  end
end
