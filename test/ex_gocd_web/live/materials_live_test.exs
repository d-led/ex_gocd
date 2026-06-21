defmodule ExGoCDWeb.MaterialsLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "renders materials page with search field and title", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/materials")

      assert html =~ "Materials"
      assert html =~ "Search for a material name or url"
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

  describe "interactive modal overlays" do
    test "opens and closes the Usages modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/materials")

      refute render(view) =~ "usages-modal"

      # Click the usages button for a specific material using its fingerprint
      html = view |> element(".icon-btn[title='Show Usages'][phx-value-fingerprint='8d78bc9f6c661806']") |> render_click()
      assert html =~ "usages-modal"
      assert html =~ "PIPELINE"
      assert html =~ "MATERIAL SETTING"

      # Close the modal
      html = view |> element("#usages-modal-ok") |> render_click()
      refute html =~ "usages-modal"
    end

    test "opens, searches, and closes the Modifications modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/materials")

      refute render(view) =~ "modifications-modal"

      # Click the modifications button for a specific material using its fingerprint
      html = view |> element(".icon-btn[title='Show Modifications'][phx-value-fingerprint='8d78bc9f6c661806']") |> render_click()
      assert html =~ "modifications-modal"
      assert html =~ "Modifications"
      assert html =~ "Search in revision, comment or username"

      # Search modifications inside modal
      html =
        view
        |> form("#mod-search-form", %{"value" => "upgrade"})
        |> render_change()
      assert html =~ "upgrade actions"

      # Close the modal
      html = view |> element("#modifications-modal-ok") |> render_click()
      refute html =~ "modifications-modal"
    end
  end
end
