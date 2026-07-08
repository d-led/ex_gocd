defmodule ExGoCD.ConfigRepos.Poller do
  @moduledoc """
  Periodically polls config repositories via git fetch/pull.
  On detected changes, re-parses YAML/JSON pipelines and upserts them.

  Uses `System.cmd("git", ...)` for git operations. Polls every 60s by default.
  """

  use GenServer
  require Logger

  alias ExGoCD.ConfigRepos

  alias ExGoCD.ConfigRepos.{ConfigRepoFile, TranslationEngine}
  alias ExGoCD.Repo

  @default_interval_ms 60_000

  # -- Client API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end

  def poll_now do
    GenServer.cast({:global, __MODULE__}, :poll)
  end

  # -- Callbacks --

  @impl true
  def init(_opts) do
    interval = Application.get_env(:ex_gocd, :config_repo_poll_interval, @default_interval_ms)
    {:ok, _} = :timer.send_interval(interval, :poll)
    # Poll immediately on startup — don't wait for the first interval
    send(self(), :poll)
    {:ok, %{first_poll: true}}
  end

  @impl true
  def handle_info(:poll, state) do
    first? = Map.get(state, :first_poll, false)
    repos = ConfigRepos.list_config_repos()
    Enum.each(repos, &poll_repo(&1, first?))
    {:noreply, %{first_poll: false}}
  end

  @impl true
  def handle_cast(:poll, state) do
    first? = Map.get(state, :first_poll, false)
    repos = ConfigRepos.list_config_repos()
    Enum.each(repos, &poll_repo(&1, first?))
    {:noreply, %{first_poll: false}}
  end

  # -- Private --

  defp poll_repo(repo, first_poll?) do
    case ensure_cloned(repo) do
      {:ok, dir} ->
        case git_pull(dir) do
          {:changed, _} ->
            Logger.info("[ConfigRepoPoller] Changes detected in repo #{repo.id}")
            parse_repo(repo, dir)

          :unchanged ->
            # Always parse on the first poll after startup so config repos
            # pick up YAML changes that were pushed while the server was
            # down or before the clone existed.
            # Also parse if this repo has never been parsed.
            if first_poll? or is_nil(repo.last_parsed_at) do
              Logger.info(
                "[ConfigRepoPoller] No git changes but repo #{repo.id} forcing parse (first_poll=#{first_poll?}, last_parsed=#{repo.last_parsed_at})"
              )

              parse_repo(repo, dir)
            else
              :ok
            end

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
           System.cmd("git", ["-C", dir, "fetch", "origin"], stderr_to_stdout: true),
         {before, 0} <-
           System.cmd("git", ["-C", dir, "rev-parse", "HEAD"], stderr_to_stdout: true),
         {_, 0} <-
           System.cmd("git", ["-C", dir, "reset", "--hard", "origin/HEAD"],
             stderr_to_stdout: true
           ),
         {after_rev, 0} <-
           System.cmd("git", ["-C", dir, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      if String.trim(before) != String.trim(after_rev), do: {:changed, ""}, else: :unchanged
    else
      {output, _} -> {:error, output}
    end
  end

  defp parse_repo(repo, dir) do
    case repo.source_type do
      "github_actions" ->
        parse_external_ci(repo, dir, ".github/workflows/*.yml", "github_workflow")

      "gitlab_ci" ->
        parse_external_ci(repo, dir, ".gitlab-ci.yml", "gitlab_pipeline")

      _ ->
        parse_gocd_pipeline(repo, dir)
    end
  end

  # --- GoCD pipeline format (existing) ---

  defp parse_gocd_pipeline(repo, dir) do
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
      update_last_parsed(repo)
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

  # --- External CI format (GitHub Actions / GitLab CI) ---

  defp parse_external_ci(repo, dir, file_pattern, file_source_type) do
    files = Path.wildcard(Path.join(dir, file_pattern))

    result =
      if files == [] do
        Logger.warning("[ConfigRepoPoller] No #{file_source_type} files found in #{dir}")
        :no_files
      else
        has_changes =
          Enum.any?(files, fn full_path ->
            rel_path = Path.relative_to(full_path, dir)
            content = File.read!(full_path)
            checksum = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
            upsert_file_record(repo, rel_path, file_source_type, checksum, content)
          end)

        if has_changes do
          case TranslationEngine.translate_and_persist_all(repo.id) do
            {:ok, count} ->
              Logger.info(
                "[ConfigRepoPoller] Translated #{count} pipelines from #{repo.source_type} repo #{repo.id}"
              )

              :ok

            {:error, reason} ->
              Logger.error("[ConfigRepoPoller] Translation failed for repo #{repo.id}: #{reason}")
              {:error, reason}
          end
        else
          Logger.debug("[ConfigRepoPoller] No changes in #{repo.source_type} repo #{repo.id}")
          :no_changes
        end
      end

    # Always update last_parsed_at so admin page shows when the repo was last checked
    update_last_parsed(repo)

    case result do
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  defp upsert_file_record(repo, rel_path, source_type, checksum, content) do
    import Ecto.Query

    existing =
      Repo.one(
        from f in ConfigRepoFile,
          where: f.config_repo_id == ^repo.id and f.path == ^rel_path
      )

    if existing && existing.checksum == checksum do
      # No change — just touch last_seen_at
      Repo.update_all(
        from(f in ConfigRepoFile, where: f.id == ^existing.id),
        set: [last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )

      false
    else
      # New or changed
      if existing do
        existing
        |> ConfigRepoFile.changeset(%{
          checksum: checksum,
          raw_content: content,
          status: "modified",
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
          parsed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

        Logger.info("[ConfigRepoPoller] Updated #{rel_path} in repo #{repo.id}")
      else
        %ConfigRepoFile{}
        |> ConfigRepoFile.changeset(%{
          config_repo_id: repo.id,
          path: rel_path,
          source_type: source_type,
          checksum: checksum,
          raw_content: content,
          status: "active",
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
          parsed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert!()

        Logger.info("[ConfigRepoPoller] Discovered #{rel_path} in repo #{repo.id}")
      end

      true
    end
  end

  defp update_last_parsed(repo) do
    ConfigRepos.update_config_repo(repo, %{
      last_parsed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      error_message: nil
    })
  end

  defp repo_dir(repo) do
    Path.join(System.tmp_dir!(), "ex_gocd_config_repo_#{repo.id}")
  end
end
