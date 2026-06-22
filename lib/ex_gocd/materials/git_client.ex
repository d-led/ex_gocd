defmodule ExGoCD.Materials.GitClient do
  @moduledoc """
  SCM client behaviour and implementations for querying Git materials.
  """

  @callback latest_revision(url :: String.t(), branch :: String.t()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Queries the latest revision details using the configured implementation.
  """
  def latest_revision(url, branch \\ "master") do
    client = Application.get_env(:ex_gocd, :git_client, __MODULE__.SystemImpl)
    client.latest_revision(url, branch)
  end

  defmodule SystemImpl do
    @behaviour ExGoCD.Materials.GitClient

    require Logger

    @impl true
    def latest_revision(url, branch) do
      # In a real environment, we run `git ls-remote` to get the HEAD revision of the branch,
      # and if we need the full commit message/committer details, we fetch/clone and run `git log`.
      # For simplicity and robust local execution:
      # 1. git ls-remote <url> <branch> to find the commit SHA.
      # 2. Return a valid modification map.
      case ExGoCD.Git.ls_remote(url, branch) do
        {:ok, sha} ->
          {:ok,
           %{
             revision: sha,
             committer_name: "SCM Poller",
             committer_email: "poller@ex-gocd.local",
             comment: "Auto-detected update via git ls-remote",
             modified_time: DateTime.utc_now() |> DateTime.truncate(:second)
           }}

        {:error, reason} ->
          Logger.error("Failed to execute git ls-remote: #{inspect(reason)}")
          {:error, :git_command_failed}
      end
    end
  end

  defmodule MockImpl do
    @behaviour ExGoCD.Materials.GitClient

    @impl true
    def latest_revision(_url, _branch) do
      # Return configurable mock revision, or helper defaults.
      # Users can set a value in Application env during test setup.
      mock_value = Application.get_env(:ex_gocd, :mock_git_revision)

      case mock_value do
        nil ->
          {:ok,
           %{
             revision: "a1b2c3d4e5f67890123456789012345678901234",
             committer_name: "Mock Committer",
             committer_email: "mock@example.com",
             comment: "Fix styling bugs",
             modified_time: ~U[2026-06-13 12:00:00Z]
           }}

        {:error, reason} ->
          {:error, reason}

        revision when is_binary(revision) ->
          {:ok,
           %{
             revision: revision,
             committer_name: "Mock Committer",
             committer_email: "mock@example.com",
             comment: "Commit message for #{revision}",
             modified_time: DateTime.utc_now() |> DateTime.truncate(:second)
           }}

        map when is_map(map) ->
          {:ok, map}
      end
    end
  end
end
