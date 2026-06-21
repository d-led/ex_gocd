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
    case :os.cmd(~c'git rev-parse --short HEAD') do
      sha when is_list(sha) ->
        sha |> to_string() |> String.trim()
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end
end
