defmodule ExGoCD.ConfigRepos.Fetcher do
  @moduledoc """
  Reads a configuration repository: clones it, or brings the clone the poller
  keeps up to date, and answers the workflow files it holds with the jobs each
  defines.

  It writes nothing to the database. Storing the chosen files is the wizard's
  job, and translating them into pipelines is the poller's; this only answers
  what the repository actually contains, so that a page can show it.
  """

  require Logger

  alias ExGoCD.ConfigRepos.{GitHubActionsParser, GitLabCIParser}

  @type file :: %{path: String.t(), job_names: [String.t()]}

  @doc """
  The repository's workflow files in path order. A file that cannot be parsed is
  still listed, with no jobs, because the user has to see that it is there.
  """
  @spec discover(map()) :: {:ok, [file()]} | {:error, String.t()}
  def discover(repo) do
    with {:ok, dir, _changes} <- fetch(repo) do
      {:ok, workflow_files(repo.source_type, dir)}
    end
  end

  @doc """
  Clones the repository into the directory the poller uses, or brings that clone
  up to date. `:changed` means the working copy moved; a fresh clone always has.
  """
  @spec fetch(map()) :: {:ok, String.t(), :changed | :unchanged} | {:error, String.t()}
  def fetch(repo) do
    dir = repo_dir(repo)

    if File.dir?(Path.join(dir, ".git")) do
      pull(dir)
    else
      clone(repo.url, dir)
    end
  end

  @doc """
  The files the poller has already recorded for this repository, with the jobs
  their stored content defines. Reads no network and no clone; a file whose
  content was never stored has no known jobs.
  """
  @spec recorded(map(), [map()]) :: [file()]
  def recorded(repo, files) do
    Enum.map(files, fn file -> describe(file.path, file.raw_content || "", repo.source_type) end)
  end

  @doc "The directory this repository is cloned into — one per repository."
  def repo_dir(%{id: id}), do: Path.join(System.tmp_dir!(), "ex_gocd_config_repo_#{id}")

  defp clone(url, dir) do
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    case git(["clone", url, dir]) do
      {:ok, output} ->
        Logger.info("[ConfigRepos.Fetcher] Cloned #{url}: #{String.slice(output, 0, 200)}")
        {:ok, dir, :changed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Fetch + reset to avoid merge conflicts, as GoCD does; the remote's default
  # branch is what a config repository tracks.
  defp pull(dir) do
    with {:ok, before} <- git(["-C", dir, "rev-parse", "HEAD"]),
         {:ok, _} <- git(["-C", dir, "fetch", "origin"]),
         {:ok, _} <- git(["-C", dir, "reset", "--hard", "origin/HEAD"]),
         {:ok, after_revision} <- git(["-C", dir, "rev-parse", "HEAD"]) do
      if String.trim(before) == String.trim(after_revision) do
        {:ok, dir, :unchanged}
      else
        {:ok, dir, :changed}
      end
    end
  end

  # Runs git, answering {:ok, output} or {:error, reason}. A git that is not
  # installed answers an error rather than raising: one repository that cannot be
  # read must not take the caller down.
  defp git(args) do
    if System.find_executable("git") do
      case System.cmd("git", args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    else
      {:error, "git is not installed in this node"}
    end
  end

  # ── Which files each kind of repository carries ─────────────────────────

  defp workflow_files("github_actions", dir) do
    dir
    |> Path.join(".github/workflows/*.{yml,yaml}")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&described(dir, &1, :github_actions))
  end

  defp workflow_files("gitlab_ci", dir) do
    path = Path.join(dir, ".gitlab-ci.yml")

    if File.exists?(path),
      do: [described(dir, path, :gitlab_ci)],
      else: []
  end

  defp workflow_files(_other, _dir), do: []

  defp described(dir, full_path, source_type) do
    describe(Path.relative_to(full_path, dir), File.read!(full_path), source_type)
  end

  defp describe(path, "", _source_type), do: %{path: path, job_names: []}

  defp describe(path, content, source_type) do
    job_names =
      case parse(source_type, content, path) do
        {:ok, ir} -> ir.jobs |> Map.keys() |> Enum.sort()
        {:error, reason} -> unparsed(path, reason)
      end

    %{path: path, job_names: job_names}
  end

  defp parse(:github_actions, content, path),
    do: GitHubActionsParser.parse_workflow(content, path)

  defp parse(:gitlab_ci, content, path),
    do: GitLabCIParser.parse_gitlab_ci(content, path)

  defp unparsed(path, reason) do
    Logger.warning("[ConfigRepos.Fetcher] Could not read #{path}: #{reason}")
    []
  end
end
