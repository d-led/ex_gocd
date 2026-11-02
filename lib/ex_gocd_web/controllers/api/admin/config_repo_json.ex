defmodule ExGoCDWeb.API.Admin.ConfigRepoJSON do
  @moduledoc """
  The shape of a config repo in the admin API.

  Spelled out rather than derived: `last_parsed_at` and `error_message` are what
  an operator checks after a refresh, `configuration` is what the parser stored.
  """

  def data(repo) do
    %{
      id: repo.id,
      url: repo.url,
      branch: repo.branch,
      source_type: repo.source_type,
      last_parsed_at: repo.last_parsed_at,
      error_message: repo.error_message
    }
  end
end
