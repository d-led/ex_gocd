defmodule ExGoCD.Git do
  @moduledoc """
  Thin wrapper around git shell commands. Centralizes all `git` invocations
  so they are testable and not scattered across the codebase.

  Uses `System.cmd/3` (not `:os.cmd/1`) for Credo compliance.
  """

  @doc """
  Runs `git ls-remote <url> <branch>` and returns the HEAD revision SHA.
  Returns `{:ok, sha}` or `{:error, reason}`.
  """
  @spec ls_remote(String.t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  def ls_remote(url, branch) do
    case cmd(["ls-remote", url, branch]) do
      {:ok, output} ->
        case String.split(output) do
          [sha, _ref | _] -> {:ok, sha}
          _ -> {:error, "invalid ls-remote output"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Runs `git rev-parse --short HEAD` in the current directory.
  Returns the short revision SHA or `nil` if not in a git repo.
  """
  @spec rev_parse_short() :: String.t() | nil
  def rev_parse_short do
    case cmd(["rev-parse", "--short", "HEAD"]) do
      {:ok, sha} -> String.trim(sha)
      {:error, _} -> nil
    end
  end

  @doc """
  Gets commit details (author name, email, message) for a revision in a local repo.
  Returns `{:ok, %{committer_name, committer_email, comment}}` or `{:error, reason}`.
  """
  @spec commit_details(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  def commit_details(repo_path, revision) do
    format = "%an%n%ae%n%s"
    full_rev = revision |> String.trim() |> then(&"#{&1}^{commit}")

    case cmd(["-C", repo_path, "log", "-1", "--format=#{format}", full_rev]) do
      {:ok, output} ->
        case String.split(output, "\n", trim: true) do
          [name, email, comment] ->
            {:ok,
             %{
               committer_name: String.trim(name),
               committer_email: String.trim(email),
               comment: String.trim(comment)
             }}

          _ ->
            {:error, "unexpected git log output"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Runs git, answering {:ok, output} or {:error, reason}.
  #
  # A git that is not installed answers an error rather than raising
  # `:enoent`: a node without git cannot poll its materials, which is a thing to
  # report, not a reason to take the caller's process down.
  defp cmd(args) do
    if System.find_executable("git") do
      case System.cmd("git", args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, String.trim(output)}
      end
    else
      {:error, "git is not installed in this node"}
    end
  end
end
