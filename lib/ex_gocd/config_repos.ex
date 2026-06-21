# Copyright 2026 ex_gocd
# ConfigRepos context — manages pipeline-as-code config repository definitions.

defmodule ExGoCD.ConfigRepos do
  @moduledoc """
  Context for managing config repositories (pipeline-as-code).
  Config repos are Git repositories containing pipeline definitions in JSON format.
  The server periodically pulls these repos and upserts pipeline configs.
  """

  alias ExGoCD.ConfigRepos.ConfigRepo
  alias ExGoCD.ConfigRepos.Parser
  alias ExGoCD.Repo

  @doc """
  Lists all config repos.
  """
  @spec list_config_repos() :: [ConfigRepo.t()]
  def list_config_repos do
    Repo.all(ConfigRepo)
  end

  @doc """
  Gets a config repo by id.
  """
  @spec get_config_repo(integer()) :: ConfigRepo.t() | nil
  def get_config_repo(id) do
    Repo.get(ConfigRepo, id)
  end

  @doc """
  Creates a config repo.
  """
  @spec create_config_repo(map()) :: {:ok, ConfigRepo.t()} | {:error, Ecto.Changeset.t()}
  def create_config_repo(attrs) do
    %ConfigRepo{}
    |> ConfigRepo.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a config repo.
  """
  @spec delete_config_repo(ConfigRepo.t()) :: {:ok, ConfigRepo.t()} | {:error, Ecto.Changeset.t()}
  def delete_config_repo(config_repo) do
    Repo.delete(config_repo)
  end

  @doc """
  Triggers a refresh of a config repo via git clone/pull.
  Currently requires explicit content; use refresh_config_repo_with_content/2.
  """
  @spec refresh_config_repo(ConfigRepo.t()) :: {:ok, integer()} | {:error, String.t()}
  def refresh_config_repo(_config_repo) do
    {:error, "direct git clone not yet implemented — use refresh_config_repo_with_content/2 to pass file contents"}
  end

  @doc """
  Refreshes a config repo with explicit file contents (for testing and API use).
  Parses the given content and upserts pipeline definitions.
  """
  @spec refresh_config_repo_with_content(ConfigRepo.t(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def refresh_config_repo_with_content(config_repo, content) when is_binary(content) do
    case Parser.parse_and_upsert(content) do
      {:ok, count} ->
        update_success(config_repo)
        {:ok, count}

      {:error, reason} ->
        update_error(config_repo, reason)
        {:error, reason}
    end
  end

  defp update_success(config_repo) do
    config_repo
    |> ConfigRepo.changeset(%{last_parsed_at: DateTime.utc_now(), error_message: nil})
    |> Repo.update()
  end

  defp update_error(config_repo, reason) do
    config_repo
    |> ConfigRepo.changeset(%{error_message: reason})
    |> Repo.update()
  end
end
