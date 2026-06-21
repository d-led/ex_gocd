# Copyright 2026 ex_gocd
# JSON rendering for Version API.

defmodule ExGoCDWeb.API.VersionJSON do
  def show(_assigns) do
    git_sha = "c8358258163d7b9833ab3b1b18a2f459999936b03a"
    %{
      _links: %{
        self: %{href: "/go/api/version"},
        doc: %{href: "https://api.gocd.org/#version"}
      },
      version: "25.4.0",
      build_number: "21793",
      git_sha: git_sha,
      full_version: "25.4.0 (21793-#{git_sha})",
      commit_url: "https://github.com/gocd/gocd/commits/#{git_sha}"
    }
  end
end
