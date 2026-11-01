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
  removing an entity stays an explicit act.
  """

  alias ExGoCD.ArtifactStores.ArtifactStore
  alias ExGoCD.ConfigRepos.ConfigRepo
  alias ExGoCD.PackageRepositories.PackageRepository
  alias ExGoCD.Repo
  alias ExGoCD.SecretConfigs.SecretConfig

  @doc """
  Restores the JSON-only sections of a captured configuration.
  """
  @spec restore(map()) :: :ok
  def restore(%{} = config) do
    restore_artifact_stores(section(config, "artifact_stores"))
    restore_secret_configs(section(config, "secret_configs"))
    restore_package_repositories(section(config, "package_repositories"))
    restore_config_repos(section(config, "config_repos"))
    :ok
  end

  defp section(config, key) do
    case Map.get(config, key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  # An artifact store has no name: the captured id is its only identity.
  defp restore_artifact_stores(stores) do
    Enum.each(stores, fn store ->
      upsert(
        %ArtifactStore{
          id: store["id"],
          plugin_id: store["plugin_id"],
          properties: store["properties"] || %{}
        },
        conflict_target: :id,
        replace: [:plugin_id, :properties]
      )
    end)
  end

  defp restore_secret_configs(secrets) do
    Enum.each(secrets, fn secret ->
      upsert(
        %SecretConfig{
          name: secret["name"],
          plugin_id: secret["plugin_id"],
          configuration: secret["configuration"] || %{},
          description: secret["description"]
        },
        conflict_target: :name,
        replace: [:plugin_id, :configuration, :description]
      )
    end)
  end

  defp restore_package_repositories(repositories) do
    Enum.each(repositories, fn repository ->
      upsert(
        %PackageRepository{
          name: repository["name"],
          plugin_id: repository["plugin_id"],
          configuration: repository["configuration"] || %{}
        },
        conflict_target: :name,
        replace: [:plugin_id, :configuration]
      )
    end)
  end

  defp restore_config_repos(config_repos) do
    Enum.each(config_repos, fn config_repo ->
      upsert(
        %ConfigRepo{
          url: config_repo["url"],
          branch: config_repo["branch"] || "main",
          material_type: config_repo["material_type"] || "git",
          source_type: config_repo["source_type"] || "gocd_pipeline",
          plugin_id: config_repo["plugin_id"],
          configuration: config_repo["configuration"] || %{}
        },
        conflict_target: [:url, :source_type],
        replace: [:branch, :material_type, :plugin_id, :configuration]
      )
    end)
  end

  defp upsert(struct, conflict_target: target, replace: replace) do
    Repo.insert(struct,
      on_conflict: {:replace, replace ++ [:updated_at]},
      conflict_target: target
    )
  end
end
