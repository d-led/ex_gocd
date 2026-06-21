defmodule ExGoCD.Materials.ScmClient do
  @moduledoc """
  Unified SCM client that dispatches to type-specific implementations
  for querying latest revisions from Git, SVN, Mercurial, and Perforce.

  In test mode (when `:scm_client` app env is set to `MockImpl`), all SCM
  queries return a fake revision without running real system commands.
  """

  alias ExGoCD.Pipelines.Material

  @callback latest_revision(url :: String.t(), branch :: String.t()) :: {:ok, map()} | {:error, any()}

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
      Git.latest_revision(mat.url, mat.branch || "master")
    end

    def latest_revision(%Material{type: "svn"} = mat) do
      Svn.latest_revision(mat.url, mat.branch || "trunk")
    end

    def latest_revision(%Material{type: "hg"} = mat) do
      Hg.latest_revision(mat.url, mat.branch || "default")
    end

    def latest_revision(%Material{type: "p4"} = mat) do
      P4.latest_revision(mat.url, mat.branch || "main")
    end

    def latest_revision(%Material{type: "tfs"} = mat) do
      Tfs.latest_revision(mat.url, mat.branch || "main")
    end

    def latest_revision(%Material{type: other}) do
      {:error, "unsupported material type: #{other}"}
    end
  end

  # ── Mock Implementation ────────────────────────────────────────────────

  defmodule MockImpl do
    @moduledoc false
    @behaviour ExGoCD.Materials.ScmClient

    @impl true
    def latest_revision(%Material{} = mat) do
      # Check :mock_scm_revision first, fall back to :mock_git_revision for backward compat
      mock_value = Application.get_env(:ex_gocd, :mock_scm_revision) ||
                   Application.get_env(:ex_gocd, :mock_git_revision)

      case mock_value do
        nil ->
          {:ok, %{
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
          # Backward compat: tests set mock_git_revision to a plain SHA string
          {:ok, %{
            revision: sha,
            committer_name: "Mock Committer",
            committer_email: "mock@example.com",
            comment: "Fix styling bugs",
            modified_time: ~U[2026-06-13 12:00:00Z]
          }}
      end
    end
  end

  # ── Git ────────────────────────────────────────────────────────────────

  defmodule Git do
    @behaviour ExGoCD.Materials.ScmClient
    require Logger

    @impl true
    def latest_revision(url, branch) do
      case System.cmd("git", ["ls-remote", url, branch]) do
        {output, 0} ->
          case String.split(output) do
            [sha, _ref | _] ->
              {:ok, %{
                revision: sha,
                committer_name: "git",
                committer_email: "git@scm.local",
                comment: "git ls-remote #{branch}",
                modified_time: ExGoCD.Materials.ScmClient.now()
              }}
            _ -> {:error, "invalid git ls-remote output"}
          end

        {err, _} ->
          Logger.error("git ls-remote failed: #{inspect(err)}")
          {:error, :git_command_failed}
      end
    end
  end

  # ── SVN ────────────────────────────────────────────────────────────────

  defmodule Svn do
    @behaviour ExGoCD.Materials.ScmClient
    require Logger

    @impl true
    def latest_revision(url, _branch) do
      case System.cmd("svn", ["info", "--show-item", "revision", url]) do
        {output, 0} ->
          rev = String.trim(output)
          {:ok, %{
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

  # ── Mercurial ──────────────────────────────────────────────────────────

  defmodule Hg do
    @behaviour ExGoCD.Materials.ScmClient
    require Logger

    @impl true
    def latest_revision(url, branch) do
      args = ["identify", url, "-r", branch]
      case System.cmd("hg", args) do
        {output, 0} ->
          rev = String.trim(output) |> String.replace(~r/\s+.*/, "")
          {:ok, %{
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

  # ── Perforce ───────────────────────────────────────────────────────────

  defmodule P4 do
    @behaviour ExGoCD.Materials.ScmClient
    require Logger

    @impl true
    def latest_revision(url, _branch) do
      # url = p4port, e.g. "ssl:perforce.example.com:1666"
      # branch = depot path, e.g. "//depot/project/main/..."
      case System.cmd("p4", ["-p", url, "changes", "-m", "1", url]) do
        {output, 0} ->
          rev = parse_p4_change(output)
          {:ok, %{
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
      # "Change 12345 on 2025/01/01 by user@client 'description'"
      case Regex.run(~r/Change (\d+)/, output) do
        [_, num] -> num
        nil -> "unknown"
      end
    end
  end

  # ── TFS ────────────────────────────────────────────────────────────────

  defmodule Tfs do
    @behaviour ExGoCD.Materials.ScmClient
    require Logger

    @impl true
    def latest_revision(url, _branch) do
      # TFS/Azure DevOps uses tf or git protocol
      Logger.warning("TFS material polling not fully implemented for #{url}")
      {:error, :tfs_not_implemented}
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  @doc false
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
