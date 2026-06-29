defmodule ExGoCD.ConfigRepos.Poller do
  @moduledoc """
  Periodically polls config repositories via git fetch/pull.
  On detected changes, re-parses YAML/JSON pipelines and upserts them.

  Uses `System.cmd("git", ...)` for git operations. Polls every 60s by default.
  """

  use GenServer
  require Logger

  alias ExGoCD.ConfigRepos

  @default_interval_ms 60_000

  # -- Client API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def poll_now do
    GenServer.cast(__MODULE__, :poll)
  end

  # -- Callbacks --

  @impl true
  def init(_opts) do
    interval = Application.get_env(:ex_gocd, :config_repo_poll_interval, @default_interval_ms)
    {:ok, _} = :timer.send_interval(interval, :poll)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    repos = ConfigRepos.list_config_repos()
    Enum.each(repos, &poll_repo/1)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:poll, state) do
    repos = ConfigRepos.list_config_repos()
    Enum.each(repos, &poll_repo/1)
    {:noreply, state}
  end

  # -- Private --

  defp poll_repo(repo) do
    case ensure_cloned(repo) do
      {:ok, dir} ->
        case git_pull(dir) do
          {:changed, _} ->
            Logger.info("[ConfigRepoPoller] Changes detected in repo #{repo.id}")
            parse_repo(repo, dir)

          :unchanged ->
            :ok

          {:error, reason} ->
            Logger.error("[ConfigRepoPoller] Git pull failed for repo #{repo.id}: #{reason}")
        end

      {:error, reason} ->
        Logger.error("[ConfigRepoPoller] Clone failed for repo #{repo.id}: #{reason}")
    end
  end

  defp ensure_cloned(repo) do
    dir = repo_dir(repo)

    if File.dir?(Path.join(dir, ".git")) do
      {:ok, dir}
    else
      File.mkdir_p!(dir)

      case System.cmd("git", ["clone", repo.url, dir], stderr_to_stdout: true) do
        {output, 0} ->
          Logger.info("[ConfigRepoPoller] Cloned #{repo.id}: #{String.slice(output, 0, 200)}")
          {:ok, dir}

        {output, _} ->
          {:error, output}
      end
    end
  end

  defp git_pull(dir) do
    # Fetch + reset to avoid merge conflicts (like GoCD's approach)
    with {_, 0} <-
           System.cmd("git", ["-C", dir, "fetch", "origin"],
             stderr_to_stdout: true,
             timeout: 30_000
           ),
         {before, 0} <-
           System.cmd("git", ["-C", dir, "rev-parse", "HEAD"], stderr_to_stdout: true),
         {_, 0} <-
           System.cmd("git", ["-C", dir, "reset", "--hard", "origin/HEAD"],
             stderr_to_stdout: true,
             timeout: 30_000
           ),
         {after_rev, 0} <-
           System.cmd("git", ["-C", dir, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      if String.trim(before) != String.trim(after_rev), do: {:changed, ""}, else: :unchanged
    else
      {output, _} -> {:error, output}
    end
  end

  defp parse_repo(repo, dir) do
    # Collect all .gocd.yaml, .gocd.json, pipeline*.yaml files
    patterns =
      Application.get_env(:ex_gocd, :config_repo_patterns, [
        "*.gocd.yaml",
        "*.gocd.json",
        "pipelines/*.yaml"
      ])

    files =
      Enum.flat_map(patterns, fn pattern ->
        Path.wildcard(Path.join(dir, pattern))
      end)
      |> Enum.uniq()

    if files == [] do
      Logger.warning("[ConfigRepoPoller] No pipeline files found in #{dir}")
      :ok
    else
      content =
        Enum.map_join(files, "\n---\n", fn f ->
          File.read!(f)
        end)

      case ConfigRepos.refresh_config_repo_with_content(repo, content) do
        {:ok, count} ->
          Logger.info("[ConfigRepoPoller] Parsed #{count} pipelines from repo #{repo.id}")
          :ok

        {:error, reason} ->
          Logger.error("[ConfigRepoPoller] Parse failed for repo #{repo.id}: #{reason}")
          :error
      end
    end
  end

  defp repo_dir(repo) do
    Path.join(System.tmp_dir!(), "ex_gocd_config_repo_#{repo.id}")
  end
end
