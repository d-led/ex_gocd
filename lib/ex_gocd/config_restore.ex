defmodule ExGoCD.ConfigRestore do
  @moduledoc """
  Restores the sections a config XML cannot express from the JSON record a
  config version keeps.

  A version stores two artefacts: `config_xml`, which is what an operator
  downloads and what GoCD itself would read, and `config_json`, which is the
  complete record. Artifact stores, secret configs, package repositories and
  config repos exist only in the JSON, so a revert that read the XML alone
  dropped them.

  Each section is upserted on the key its schema keeps unique, so a restore
  adds and updates but never deletes: it puts back what the version held, and
  removing an entity stays an explicit act. The whole restore is one
  transaction, so a version that cannot be restored in full leaves nothing
  half-restored, and it goes through each schema's changeset, so a record that
  does not fit its schema comes back as a message rather than as a database
  error.
  """

  alias ExGoCD.ArtifactStores.ArtifactStore
  alias ExGoCD.ConfigRepos.ConfigRepo
  alias ExGoCD.PackageRepositories.PackageRepository
  alias ExGoCD.Repo
  alias ExGoCD.SecretConfigs.SecretConfig

  @doc """
  Restores the JSON-only sections of a captured configuration.

  Returns `:ok`, or `{:error, message}` naming what could not be stored. Nothing
  is stored in that case.
  """
  @spec restore(map()) :: :ok | {:error, String.t()}
  def restore(%{} = config) do
    case Repo.transaction(fn -> restore_or_roll_back(config) end) do
      {:ok, :ok} -> :ok
      {:error, message} -> {:error, message}
    end
  end

  defp restore_or_roll_back(config) do
    with :ok <- restore_artifact_stores(section(config, "artifact_stores")),
         :ok <- restore_secret_configs(section(config, "secret_configs")),
         :ok <- restore_package_repositories(section(config, "package_repositories")),
         :ok <- restore_config_repos(section(config, "config_repos")) do
      :ok
    else
      {:error, message} -> Repo.rollback(message)
    end
  end

  defp section(config, key) do
    case Map.get(config, key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  # An artifact store has no name: the captured id is its only identity.
  defp restore_artifact_stores(stores) do
    upsert_all(
      stores,
      fn store ->
        ArtifactStore.changeset(%ArtifactStore{id: store["id"]}, %{
          plugin_id: store["plugin_id"],
          properties: store["properties"] || %{}
        })
      end,
      conflict_target: :id,
      replace: [:plugin_id, :properties]
    )
  end

  defp restore_secret_configs(secrets) do
    upsert_all(
      secrets,
      fn secret ->
        SecretConfig.changeset(%SecretConfig{}, %{
          name: secret["name"],
          plugin_id: secret["plugin_id"],
          configuration: secret["configuration"] || %{},
          description: secret["description"]
        })
      end,
      conflict_target: :name,
      replace: [:plugin_id, :configuration, :description]
    )
  end

  defp restore_package_repositories(repositories) do
    upsert_all(
      repositories,
      fn repository ->
        PackageRepository.changeset(%PackageRepository{}, %{
          name: repository["name"],
          plugin_id: repository["plugin_id"],
          configuration: repository["configuration"] || %{}
        })
      end,
      conflict_target: :name,
      replace: [:plugin_id, :configuration]
    )
  end

  defp restore_config_repos(config_repos) do
    upsert_all(
      config_repos,
      fn config_repo ->
        ConfigRepo.changeset(%ConfigRepo{}, %{
          url: config_repo["url"],
          branch: config_repo["branch"] || "main",
          material_type: config_repo["material_type"] || "git",
          source_type: config_repo["source_type"] || "gocd_pipeline",
          plugin_id: config_repo["plugin_id"],
          configuration: config_repo["configuration"] || %{}
        })
      end,
      conflict_target: [:url, :source_type],
      replace: [:branch, :material_type, :plugin_id, :configuration]
    )
  end

  defp upsert_all(records, build, conflict_target: target, replace: replace) do
    Enum.reduce_while(records, :ok, fn record, :ok ->
      case Repo.insert(build.(record),
             on_conflict: {:replace, replace ++ [:updated_at]},
             conflict_target: target
           ) do
        {:ok, _stored} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, describe(changeset)}}
      end
    end)
  end

  defp describe(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
