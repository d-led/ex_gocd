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
      case ExGoCD.Git.ls_remote(url, branch) do
        {:ok, sha} ->
          # Shallow-clone to get real commit metadata.  git ls-remote only
          # returns the SHA — we need author, email, message, and timestamp
          # for a proper audit trail in the VSM and materials views.
          case fetch_commit_details(url, branch, sha) do
            {:ok, details} ->
              {:ok, Map.put(details, :revision, sha)}

            {:error, _reason} ->
              # Clone failed — fall back to the SHA-only entry rather than
              # blocking the pipeline trigger.
              Logger.warning(
                "SCM Poller: could not fetch commit details for #{url}@#{branch} (#{String.slice(sha, 0, 8)}), using revision-only entry"
              )

              {:ok,
               %{
                 revision: sha,
                 committer_name: "git",
                 committer_email: "",
                 comment: String.slice(sha, 0, 8),
                 modified_time: DateTime.utc_now() |> DateTime.truncate(:second)
               }}
          end

        {:error, reason} ->
          Logger.error("Failed to execute git ls-remote: #{inspect(reason)}")
          {:error, :git_command_failed}
      end
    end

    # Shallow-clone the repo into a temp directory, extract commit metadata,
    # then clean up.  depth=1 + single-branch keeps it fast.
    defp fetch_commit_details(url, branch, sha) do
      tmp = System.tmp_dir!()
      dir = Path.join(tmp, "ex_gocd_git_#{:erlang.unique_integer([:positive])}")

      try do
        clone_args = [
          "clone", "--depth", "1", "--single-branch",
          "--branch", branch, url, dir
        ]

        case System.cmd("git", clone_args, stderr_to_stdout: true) do
          {_, 0} ->
            details = ExGoCD.Git.commit_details(dir, sha)

            # Also get the committer timestamp
            date =
              case System.cmd("git", ["-C", dir, "log", "-1", "--format=%aI", sha]) do
                {dt, 0} ->
                  case DateTime.from_iso8601(String.trim(dt)) do
                    {:ok, dt, _} -> dt
                    _ -> DateTime.utc_now() |> DateTime.truncate(:second)
                  end

                _ ->
                  DateTime.utc_now() |> DateTime.truncate(:second)
              end

            case details do
              {:ok, map} -> {:ok, Map.put(map, :modified_time, date)}
              {:error, _} -> {:error, :no_details}
            end

          {err, _} ->
            Logger.debug("SCM Poller: shallow clone failed for #{url}: #{String.slice(err, 0, 200)}")
            {:error, :clone_failed}
        end
      after
        File.rm_rf(dir)
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
