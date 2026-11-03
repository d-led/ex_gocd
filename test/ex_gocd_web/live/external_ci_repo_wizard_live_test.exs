defmodule ExGoCDWeb.ExternalCIRepoWizardLiveTest do
  use ExGoCDWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ExGoCD.ConfigRepos.{ConfigRepo, ConfigRepoFile, ConfigRepoFileSelection, Fetcher}
  alias ExGoCD.GitRepository
  alias ExGoCD.Repo

  @moduletag :tmp_dir

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

    test "a filled step one stores the repository and shows the workflows it holds", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      origin = workflows_repository(tmp_dir, ["compile", "test"])

      {:ok, view, _html} = live(conn, ~p"/admin/config_repos/new")

      html = submit_step_one(view, "file://#{origin}", "main")
      forget_clone_on_exit(Repo.one!(ConfigRepo))

      assert html =~ ".github/workflows/build.yml"

      assert [stored] = Repo.all(ConfigRepo)
      assert stored.url == "file://#{origin}"
      assert stored.branch == "main"
      assert stored.source_type == "github_actions"
    end

    test "finishing the wizard records the chosen file with the jobs it found", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      origin = workflows_repository(tmp_dir, ["compile", "test"])

      {:ok, view, _html} = live(conn, ~p"/admin/config_repos/new")

      submit_step_one(view, "file://#{origin}", "main")
      forget_clone_on_exit(Repo.one!(ConfigRepo))

      view |> element("button[phx-click='step2_continue']") |> render_click()
      view |> element("button[phx-click='step3_next']") |> render_click()
      view |> element("button[phx-click='save_all']") |> render_click()

      assert [file] = Repo.all(ConfigRepoFile)
      assert file.path == ".github/workflows/build.yml"

      assert [selection] = Repo.all(ConfigRepoFileSelection)
      assert selection.config_repo_file_id == file.id
      assert selection.selected_jobs == ["compile", "test"]
    end

    test "says why it could not read a repository, and keeps that URL free", %{
      conn: conn,
      tmp_dir: tmp_dir
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/config_repos/new")

      html = submit_step_one(view, "file://#{Path.join(tmp_dir, "gone")}", "main")

      assert html =~ "Could not read the repository"
      assert Repo.all(ConfigRepo) == []
    end
  end

  defp workflows_repository(tmp_dir, jobs) do
    GitRepository.create(Path.join(tmp_dir, "origin"), %{
      ".github/workflows/build.yml" => GitRepository.github_workflow(jobs)
    })
  end

  # The wizard clones the repository into the poller's directory; the sandbox
  # rolls the row back, so the clone is removed here — by the id captured while
  # the row was still there, because on_exit runs outside the sandbox.
  defp forget_clone_on_exit(config_repo) do
    on_exit(fn -> File.rm_rf!(Fetcher.repo_dir(config_repo)) end)
  end

  defp submit_step_one(view, url, branch) do
    view
    |> form("form[phx-submit='step1_next']", %{"repo_url" => url, "branch" => branch})
    |> render_submit()
  end
end
