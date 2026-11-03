# Copyright 2026 ex_gocd
# Admin API for config repositories — CRUD + refresh (pipeline-as-code).

defmodule ExGoCDWeb.API.Admin.ConfigRepoController do
  use ExGoCDWeb, :controller

  plug ExGoCDWeb.Plugs.GoCDConfirm

  alias ExGoCD.ConfigRepos
  alias ExGoCD.ConfigRepos.Poller
  alias ExGoCDWeb.API.Admin.ConfigRepoJSON

  action_fallback ExGoCDWeb.FallbackController

  @doc """
  GET /api/admin/config_repos
  """
  def index(conn, _params) do
    repos = ConfigRepos.list_config_repos()
    json(conn, %{config_repos: Enum.map(repos, &ConfigRepoJSON.data/1)})
  end

  @doc """
  GET /api/admin/config_repos/:id
  """
  def show(conn, %{"id" => id}) do
    case ConfigRepos.get_config_repo(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Config repo not found"})

      repo ->
        json(conn, %{config_repo: ConfigRepoJSON.data(repo)})
    end
  end

  @doc """
  POST /api/admin/config_repos
  """
  def create(conn, params) do
    attrs = %{
      url: params["url"],
      branch: params["branch"] || "main",
      source_type: params["source_type"] || "gocd_pipeline"
    }

    case ConfigRepos.create_config_repo(attrs) do
      {:ok, repo} ->
        # Trigger immediate poll
        Poller.poll_now()

        conn
        |> put_status(:created)
        |> json(%{config_repo: repo})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_errors(changeset)})
    end
  end

  @doc """
  PUT /api/admin/config_repos/:id — update
  """
  def update(conn, %{"id" => id} = params) do
    case ConfigRepos.get_config_repo(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Config repo not found"})

      repo ->
        attrs = %{
          url: params["url"] || repo.url,
          branch: params["branch"] || repo.branch,
          source_type: params["source_type"] || repo.source_type
        }

        case ConfigRepos.update_config_repo(repo, attrs) do
          {:ok, updated} ->
            json(conn, %{config_repo: ConfigRepoJSON.data(updated)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Validation failed", details: format_errors(changeset)})
        end
    end
  end

  @doc """
  DELETE /api/admin/config_repos/:id
  """
  def delete(conn, %{"id" => id}) do
    case ConfigRepos.get_config_repo(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Config repo not found"})

      repo ->
        {:ok, _} = ConfigRepos.delete_config_repo(repo)
        json(conn, %{message: "Config repo deleted"})
    end
  end

  @doc """
  POST /api/admin/config_repos/:id/refresh
  """
  def refresh(conn, %{"id" => id}) do
    case ConfigRepos.get_config_repo(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Config repo not found"})

      repo ->
        if repo.url && String.starts_with?(repo.url, ["http://", "https://", "git@"]) do
          # Trigger immediate poll
          Poller.poll_now()

          repo = ConfigRepos.get_config_repo(id)
          json(conn, %{config_repo: ConfigRepoJSON.data(repo)})
        else
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Repo URL must be a valid git URL"})
        end
    end
  end
end
