defmodule ExGoCD.Svn do
  @moduledoc """
  Thin wrapper around `svn` shell commands. Centralizes all Subversion
  command invocations so they are testable and not scattered across the codebase.

  Uses `System.cmd/3` (not `:os.cmd/1`) for Credo compliance.

  Handles multiple authentication modes:
    - No auth (public repos)
    - Username only (uses cached credentials from ~/.subversion)
    - Username + password (explicit credentials)

  Based on GoCD original: domain/src/main/java/.../svn/SvnCommand.java
  """

  @doc """
  Returns the latest revision number for a Subversion URL.
  Equivalent to: `svn info --show-item revision <URL>`

  Returns `{:ok, revision_string}` or `{:error, reason}`.
  """
  @spec info_revision(String.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
  def info_revision(url, opts \\ []) do
    case run_svn(["info", "--show-item", "revision" | svn_auth_args(opts) ++ [url]]) do
      {output, 0} -> {:ok, String.trim(output)}
      {err, _} -> {:error, err}
    end
  end

  @doc """
  Returns structured info about a remote Subversion URL.
  Runs: `svn info --xml <URL>`
  Parses the XML to extract: revision, author, date, root, uuid.

  Returns `{:ok, info_map}` or `{:error, reason}`.
  """
  @spec remote_info(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def remote_info(url, opts \\ []) do
    case run_svn(["info", "--xml" | svn_auth_args(opts) ++ [url]]) do
      {output, 0} -> {:ok, parse_info_xml(output)}
      {err, _} -> {:error, err}
    end
  end

  @doc """
  Returns the latest modification details via `svn log --xml -l 1`.
  Extracts: revision, author, date, message.

  Returns `{:ok, mod_map}` or `{:error, reason}`.
  """
  @spec latest_modification(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def latest_modification(url, opts \\ []) do
    case run_svn(["log", "--xml", "-l", "1" | svn_auth_args(opts) ++ [url]]) do
      {output, 0} -> {:ok, parse_log_xml(output)}
      {err, _} -> {:error, err}
    end
  end

  @doc """
  Checks out a Subversion repository to a local directory.
  Equivalent to: `svn checkout --non-interactive -r REV URL DEST`

  Returns `{:ok, output}` or `{:error, reason}`.
  """
  @spec checkout(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, any()}
  def checkout(url, dest, revision, opts \\ []) do
    check_externals = Keyword.get(opts, :check_externals, false)
    externals_flag = if check_externals, do: [], else: ["--ignore-externals"]

    args =
      ["checkout", "--non-interactive", "-r", revision] ++
        externals_flag ++ svn_auth_args(opts) ++ [url, dest]

    case run_svn(args) do
      {output, 0} -> {:ok, output}
      {err, code} -> {:error, "svn checkout failed (exit #{code}): #{err}"}
    end
  end

  @doc """
  Updates a working copy to a specific revision.
  Equivalent to: `svn update --non-interactive -r REV`

  Returns `{:ok, output}` or `{:error, reason}`.
  """
  @spec update(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
  def update(working_dir, revision, opts \\ []) do
    args = ["update", "--non-interactive", "-r", revision | svn_auth_args(opts) ++ [working_dir]]

    case run_svn(args, cd: working_dir) do
      {output, 0} -> {:ok, output}
      {err, code} -> {:error, "svn update failed (exit #{code}): #{err}"}
    end
  end

  @doc """
  Cleans up and reverts a working copy.
  Runs `svn cleanup --non-interactive` then `svn revert -R .`

  Returns `{:ok, output}` or `{:error, reason}`.
  """
  @spec cleanup_and_revert(String.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
  def cleanup_and_revert(working_dir, opts \\ []) do
    with {:ok, cleanup_out} <-
           run_svn_cd(["cleanup", "--non-interactive" | svn_auth_args(opts)], working_dir),
         {:ok, revert_out} <- run_svn_cd(["revert", "-R", "."], working_dir) do
      {:ok, cleanup_out <> "\n" <> revert_out}
    end
  end

  @doc """
  Checks if `svn` is available on the system PATH.
  Returns `true` or `false`.
  """
  @spec available?() :: boolean()
  def available? do
    case System.cmd("sh", ["-c", "command -v svn"]) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Returns the svn version string, e.g. "svn, version 1.14.0 (r1876290)"
  """
  @spec version() :: {:ok, String.t()} | {:error, any()}
  def version do
    case run_svn(["--version", "--quiet"]) do
      {output, 0} -> {:ok, String.trim(output)}
      {err, _} -> {:error, err}
    end
  end

  # ── Private Helpers ─────────────────────────────────────────────────

  defp run_svn(args, run_opts \\ []) do
    System.cmd("svn", args, Keyword.merge([stderr_to_stdout: true], run_opts))
  end

  defp run_svn_cd(args, working_dir) do
    case run_svn(args, cd: working_dir) do
      {output, 0} -> {:ok, output}
      {err, code} -> {:error, "svn command failed (exit #{code}): #{err}"}
    end
  end

  @doc false
  def svn_auth_args(opts) do
    username = blank_to_nil(Keyword.get(opts, :username))
    password = blank_to_nil(Keyword.get(opts, :password))

    cond do
      username && password ->
        ["--username", username, "--password", password, "--no-auth-cache", "--non-interactive"]

      username ->
        ["--username", username, "--no-auth-cache", "--non-interactive"]

      true ->
        ["--non-interactive"]
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(val), do: val

  # ── XML Parsers ─────────────────────────────────────────────────────

  @doc false
  def parse_info_xml(xml_string) do
    # Minimal XML parser for svn info --xml output.
    # We use simple regex parsing to avoid adding an XML dependency.
    # Format: <info><entry ...><url>...</url><commit revision="X"><author>...</author><date>...</date></commit></entry></info>
    %{
      revision: extract_xml(xml_string, ~r/revision="(\d+)"/, 1),
      author: extract_xml(xml_string, ~r/<author>(.*?)<\/author>/, 1),
      date: extract_xml(xml_string, ~r/<date>(.*?)<\/date>/, 1),
      url: extract_xml(xml_string, ~r/<url>(.*?)<\/url>/, 1),
      root: extract_xml(xml_string, ~r/<root>(.*?)<\/root>/, 1),
      uuid: extract_xml(xml_string, ~r/<uuid>(.*?)<\/uuid>/, 1)
    }
  end

  @doc false
  def parse_log_xml(xml_string) do
    # Minimal XML parser for svn log --xml output.
    # Format: <log><logentry revision="X"><author>...</author><date>...</date><msg>...</msg></logentry></log>
    %{
      revision: extract_xml(xml_string, ~r/revision="(\d+)"/, 1),
      author: extract_xml(xml_string, ~r/<author>(.*?)<\/author>/, 1),
      date: extract_xml(xml_string, ~r/<date>(.*?)<\/date>/, 1),
      message: extract_xml(xml_string, ~r/<msg>(.*?)<\/msg>/s, 1) |> String.trim()
    }
  end

  defp extract_xml(xml, regex, _capture_idx) do
    case Regex.run(regex, xml) do
      [_, match] -> match
      nil -> ""
    end
  end
end
