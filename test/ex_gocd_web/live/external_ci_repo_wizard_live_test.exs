defmodule ExGoCDWeb.ExternalCIRepoWizardLiveTest do
  use ExGoCDWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ExGoCD.ConfigRepos.ConfigRepo
  alias ExGoCD.ConfigRepos.ConfigRepoFile
  alias ExGoCD.ConfigRepos.ConfigRepoFileSelection
  alias ExGoCD.Repo

  describe "the external CI repository wizard" do
    test "says so, rather than failing, when the id is not one it could hold", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/config_repos", flash: flash}}} =
               live(conn, ~p"/admin/config_repos/#{Ecto.UUID.generate()}/edit")

      assert flash["error"] =~ "not found"
    end

    test "asks for a repository before it goes on", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/config_repos/new")

      html = submit_step_one(view, "", "main")

      assert html =~ "Repository URL is required"
      assert Repo.all(ConfigRepo) == []
    end

    test "refuses something that is not a repository URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/config_repos/new")

      html = submit_step_one(view, "not-a-url", "main")

      assert html =~ "Must be a valid git URL"
      assert Repo.all(ConfigRepo) == []
    end

    test "a filled step one stores the repository and shows the workflows it found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/config_repos/new")

      html = submit_step_one(view, "https://github.com/acme/ci.git", "trunk")

      assert html =~ ".github/workflows/gradle.yml"

      assert [stored] = Repo.all(ConfigRepo)
      assert stored.url == "https://github.com/acme/ci.git"
      assert stored.branch == "trunk"
      assert stored.source_type == "github_actions"
    end

    test "finishing the wizard records the chosen file with the jobs it discovered", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/config_repos/new")

      submit_step_one(view, "https://github.com/acme/ci.git", "main")

      view |> element("button[phx-click='step2_continue']") |> render_click()
      view |> element("button[phx-click='step3_next']") |> render_click()
      view |> element("button[phx-click='save_all']") |> render_click()

      assert [file] = Repo.all(ConfigRepoFile)
      assert file.path == ".github/workflows/gradle.yml"

      assert [selection] = Repo.all(ConfigRepoFileSelection)
      assert selection.config_repo_file_id == file.id
      assert Enum.sort(selection.selected_jobs) == ["mutation-testing", "property-based-testing"]
    end
  end

  defp submit_step_one(view, url, branch) do
    view
    |> form("form[phx-submit='step1_next']", %{"repo_url" => url, "branch" => branch})
    |> render_submit()
  end
end
