defmodule ExGoCD.Materials.ScmClient do
  @moduledoc """
  Unified SCM client that dispatches to type-specific implementations
  for querying latest revisions from Git, SVN, Mercurial, and Perforce.

  In test mode (when `:scm_client` app env is set to `MockImpl`), all SCM
  queries return a fake revision without running real system commands.
  """

  alias ExGoCD.Pipelines.Material

  @callback latest_revision(Material.t()) :: {:ok, map()} | {:error, any()}

  @doc """
  Queries the latest revision for a material, dispatching by type.
  Uses MockImpl in test mode, real SystemImpl otherwise.
  Returns {:ok, modification_map} or {:error, reason}.
  """
  @spec latest_revision(Material.t()) :: {:ok, map()} | {:error, String.t()}
  def latest_revision(%Material{} = mat) do
    impl = Application.get_env(:ex_gocd, :scm_client, __MODULE__.SystemImpl)
    impl.latest_revision(mat)
  end

  # ── System Implementation ──────────────────────────────────────────────

  defmodule SystemImpl do
    @moduledoc false
    @behaviour ExGoCD.Materials.ScmClient

    @impl true
    def latest_revision(%Material{type: "git"} = mat) do
      __MODULE__.Git.latest_revision(mat.url, mat.branch || "master")
    end

    def latest_revision(%Material{type: "svn"} = mat) do
      __MODULE__.Svn.latest_revision(mat.url, mat.branch || "trunk")
    end

    def latest_revision(%Material{type: "hg"} = mat) do
      __MODULE__.Hg.latest_revision(mat.url, mat.branch || "default")
    end

    def latest_revision(%Material{type: "p4"} = mat) do
      __MODULE__.P4.latest_revision(mat.url, mat.branch || "main")
    end

    def latest_revision(%Material{type: "tfs"} = mat) do
      __MODULE__.Tfs.latest_revision(mat.url, mat.branch || "main")
    end

    def latest_revision(%Material{type: other}) do
      {:error, "unsupported material type: #{other}"}
    end

    # Inner type-specific implementations (called via __MODULE__ above)

    defmodule Git do
      @moduledoc false
      require Logger

      def latest_revision(url, branch) do
        case ExGoCD.Git.ls_remote(url, branch) do
          {:ok, sha} ->
            details = resolve_commit_details(url, sha)

            {:ok,
             %{
               revision: sha,
               committer_name: details[:committer_name] || "git",
               committer_email: details[:committer_email] || "git@scm.local",
               comment: details[:comment] || "Revision #{String.slice(sha, 0, 8)}",
               modified_time: ExGoCD.Materials.ScmClient.now()
             }}

          {:error, reason} ->
            Logger.error("git ls-remote failed: #{inspect(reason)}")
            {:error, :git_command_failed}
        end
      end

      defp resolve_commit_details(url, sha) do
        try do
          if File.dir?(url) do
            case ExGoCD.Git.commit_details(url, sha) do
              {:ok, details} -> details
              _ -> %{}
            end
          else
            # For remote URLs, try current working directory (dogfood scenario)
            case ExGoCD.Git.commit_details(".", sha) do
              {:ok, details} -> details
              _ -> %{}
            end
          end
        rescue
          _ -> %{}
        end
      end
    end

    defmodule Svn do
      @moduledoc false
      require Logger

      def latest_revision(url, _branch) do
        case System.cmd("svn", ["info", "--show-item", "revision", url]) do
          {output, 0} ->
            rev = String.trim(output)

            {:ok,
             %{
               revision: rev,
               committer_name: "svn",
               committer_email: "svn@scm.local",
               comment: "svn revision #{rev}",
               modified_time: ExGoCD.Materials.ScmClient.now()
             }}

          {err, _} ->
            Logger.error("svn info failed: #{inspect(err)}")
            {:error, :svn_command_failed}
        end
      end
    end

    defmodule Hg do
      @moduledoc false
      require Logger

      def latest_revision(url, branch) do
        args = ["identify", url, "-r", branch]

        case System.cmd("hg", args) do
          {output, 0} ->
            rev = String.trim(output) |> String.replace(~r/\s+.*/, "")

            {:ok,
             %{
               revision: rev,
               committer_name: "hg",
               committer_email: "hg@scm.local",
               comment: "hg identify #{branch}",
               modified_time: ExGoCD.Materials.ScmClient.now()
             }}

          {err, _} ->
            Logger.error("hg identify failed: #{inspect(err)}")
            {:error, :hg_command_failed}
        end
      end
    end

    defmodule P4 do
      @moduledoc false
      require Logger

      def latest_revision(url, _branch) do
        case System.cmd("p4", ["-p", url, "changes", "-m", "1", url]) do
          {output, 0} ->
            rev = parse_p4_change(output)

            {:ok,
             %{
               revision: rev,
               committer_name: "p4",
               committer_email: "p4@scm.local",
               comment: "p4 change #{rev}",
               modified_time: ExGoCD.Materials.ScmClient.now()
             }}

          {err, _} ->
            Logger.error("p4 changes failed: #{inspect(err)}")
            {:error, :p4_command_failed}
        end
      end

      defp parse_p4_change(output) do
        case Regex.run(~r/Change (\d+)/, output) do
          [_, num] -> num
          nil -> "unknown"
        end
      end
    end

    defmodule Tfs do
      @moduledoc false
      require Logger

      def latest_revision(url, _branch) do
        Logger.warning("TFS material polling not fully implemented for #{url}")
        {:error, :tfs_not_implemented}
      end
    end
  end

  # ── Mock Implementation ────────────────────────────────────────────────

  defmodule MockImpl do
    @moduledoc false
    @behaviour ExGoCD.Materials.ScmClient

    @impl true
    def latest_revision(%Material{} = _mat) do
      mock_value =
        Application.get_env(:ex_gocd, :mock_scm_revision) ||
          Application.get_env(:ex_gocd, :mock_git_revision)

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

        {:ok, map} ->
          {:ok, map}

        sha when is_binary(sha) ->
          {:ok,
           %{
             revision: sha,
             committer_name: "Mock Committer",
             committer_email: "mock@example.com",
             comment: "Fix styling bugs",
             modified_time: ~U[2026-06-13 12:00:00Z]
           }}
      end
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  @doc false
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
