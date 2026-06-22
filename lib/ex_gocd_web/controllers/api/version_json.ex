# Copyright 2026 ex_gocd
# JSON rendering for Version API.

defmodule ExGoCDWeb.API.VersionJSON do
  @app :ex_gocd

  def show(_assigns) do
    vsn = to_string(Application.spec(@app, :vsn))
    git_sha = git_sha()
    %{
      _links: %{
        self: %{href: "/go/api/version"},
        doc: %{href: "https://github.com/d-led/ex_gocd#api"}
      },
      version: vsn,
      build_number: vsn,
      git_sha: git_sha,
      full_version: "#{vsn} (#{git_sha})",
      commit_url: "https://github.com/d-led/ex_gocd/commits/#{git_sha}"
    }
  end

  defp git_sha do
    # CI: use GITHUB_SHA; local: use git rev-parse
    case System.get_env("GITHUB_SHA") do
      sha when is_binary(sha) and byte_size(sha) > 0 ->
        String.slice(sha, 0, 7)
      _ ->
        case System.cmd("git", ["rev-parse", "--short", "HEAD"]) do
          {sha, 0} -> String.trim(sha)
          _ -> "unknown"
        end
    end
  rescue
    _ -> "unknown"
  end
end
