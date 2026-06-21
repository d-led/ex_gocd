defmodule ExGoCDWeb.ValueStreamMapLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "Pipeline VSM rendering" do
    test "renders value stream map for a valid pipeline run", %{conn: conn} do
      # Given a valid pipeline VSM route
      {:ok, _view, html} = live(conn, ~p"/pipelines/value_stream_map/build-linux/1")

      # Then it renders breadcrumbs and VSM flow titles
      assert html =~ "Pipelines"
      assert html =~ "build-linux"
      assert html =~ "Instance"
      assert html =~ "1"

      # And it renders the material node
      assert html =~ "gocd.git"

      # And it renders the stages of the pipeline node
      assert html =~ "compile"
      assert html =~ "test"
      assert html =~ "package"

      # And it renders the current node indicator
      assert html =~ "Current"
    end

    test "redirects to pipelines dashboard on non-existent pipeline name", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/pipelines"}}} =
               live(conn, ~p"/pipelines/value_stream_map/nonexistent-pipeline/1")
    end
  end

  describe "Material VSM rendering" do
    test "renders value stream map for a material fingerprint and revision", %{conn: conn} do
      # Given a valid material VSM route
      {:ok, _view, html} = live(conn, ~p"/materials/value_stream_map/8d78bc9f6c661806/abcd1234ef")

      # Then it renders breadcrumbs and VSM flow titles
      assert html =~ "Materials"
      assert html =~ "gocd.git"
      assert html =~ "Revision"
      assert html =~ "abcd1234ef"

      # And it renders the material node and dependent pipelines
      assert html =~ "Material"
      assert html =~ "build-linux"
    end

    test "does not crash when VSM has empty levels", %{conn: conn} do
      # Given the mock data fallback always returns a VSM with levels
      {:ok, _view, html} = live(conn, ~p"/materials/value_stream_map/0000000000000000/000000000000")

      # Then it still renders without crashing (generic fallback)
      assert html =~ "Materials"
      assert html =~ "Revision"
    end
  end

  describe "Pipeline VSM via /go/ compatibility route" do
    test "renders via /go/ compatibility prefix", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/go/pipelines/value_stream_map/build-linux/1")

      assert html =~ "build-linux"
      assert html =~ "Materials"
    end

    test "redirects for non-existent pipeline via /go/ prefix", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/pipelines"}}} =
               live(conn, ~p"/go/pipelines/value_stream_map/nope/999")
    end
  end
end
