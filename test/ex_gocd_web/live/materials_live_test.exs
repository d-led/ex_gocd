defmodule ExGoCDWeb.MaterialsLiveTest do
  use ExGoCDWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "renders materials page with search field and title", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/materials")

      assert html =~ "Materials"
      assert html =~ "Search materials"
      assert html =~ "Used in Pipelines"
    end

    test "renders mock materials list in test mode", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/materials")

      # Should render repository URLs from MockData (e.g. github.com/gocd/gocd.git)
      assert html =~ "https://github.com/gocd/gocd.git"
      assert html =~ "git"
      assert html =~ "master"
    end
  end

  describe "search functionality" do
    test "filters materials list by SCM URL / branch", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/materials")

      # Search for docs-build material (contains docs.git)
      view
      |> form("#material-search-form", %{"value" => "docs.git"})
      |> render_change()

      html = render(view)
      assert html =~ "https://github.com/gocd/docs.git"
      refute html =~ "https://github.com/gocd/gocd.git"
    end

    test "filters materials list by branch name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/materials")

      # Search for release branch (deploy-production material has branch "release")
      view
      |> form("#material-search-form", %{"value" => "release"})
      |> render_change()

      html = render(view)
      assert html =~ "https://github.com/gocd/gocd.git"
      assert html =~ "release"
    end

    test "displays empty state message when no materials match", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/materials")

      view
      |> form("#material-search-form", %{"value" => "nonexistent-material-repo"})
      |> render_change()

      html = render(view)
      assert html =~ "No materials found"
      assert html =~ "Try refining your search term"
    end
  end
end
