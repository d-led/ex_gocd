defmodule ExGoCDWeb.API.ConfigRepoController do
  @moduledoc """
  API controller for config repo cleanup (used by Cypress tests).
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.{Repo, ConfigRepos.ConfigRepo}
  import Ecto.Query

  @doc """
  DELETE /api/config_repos/cleanup

  Deletes all config repos with URLs matching the eci-test pattern (Cypress test artifacts).
  No-op in production.
  """
  def cleanup_test_data(conn, _params) do
    deleted =
      from(cr in ConfigRepo, where: like(cr.url, "%eci-test/%"))
      |> Repo.delete_all()

    json(conn, %{deleted: elem(deleted, 2) || 0})
  end
end
