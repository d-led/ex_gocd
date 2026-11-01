defmodule ExGoCD.ConfigRestoreTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.ArtifactStores.ArtifactStore
  alias ExGoCD.ConfigRepos.ConfigRepo
  alias ExGoCD.ConfigRestore
  alias ExGoCD.PackageRepositories.PackageRepository
  alias ExGoCD.Repo
  alias ExGoCD.SecretConfigs.SecretConfig

  describe "restore/1" do
    test "brings back the sections a config XML cannot carry" do
      store_id = "8b1e41f1-6b6f-4a2b-9d3f-1c5f1d2a7e10"

      config = %{
        "artifact_stores" => [
          %{
            "id" => store_id,
            "plugin_id" => "cd.go.artifact.docker.registry",
            "properties" => %{"RegistryURL" => "https://registry.test"}
          }
        ],
        "secret_configs" => [
          %{
            "id" => 7,
            "name" => "vault-prod",
            "plugin_id" => "cd.go.secrets.vault",
            "configuration" => %{"address" => "https://vault.test"},
            "description" => "production vault"
          }
        ],
        "package_repositories" => [
          %{
            "id" => 3,
            "name" => "acme-npm",
            "plugin_id" => "cd.go.reporter.artifact.npm",
            "configuration" => %{"RepositoryURL" => "https://npm.test"}
          }
        ],
        "config_repos" => [
          %{
            "id" => 9,
            "url" => "https://github.com/acme/config.git",
            "branch" => "trunk",
            "material_type" => "git",
            "source_type" => "gocd_pipeline",
            "plugin_id" => "cd.go.config-repo.yaml",
            "configuration" => %{"pattern" => "*.gocd.yaml"}
          }
        ]
      }

      assert :ok = ConfigRestore.restore(config)

      assert %ArtifactStore{plugin_id: "cd.go.artifact.docker.registry"} =
               Repo.get(ArtifactStore, store_id)

      assert %SecretConfig{configuration: %{"address" => "https://vault.test"}} =
               Repo.get_by(SecretConfig, name: "vault-prod")

      assert %PackageRepository{} = Repo.get_by(PackageRepository, name: "acme-npm")

      assert %ConfigRepo{branch: "trunk"} =
               Repo.get_by(ConfigRepo, url: "https://github.com/acme/config.git")
    end

    test "a restored section replaces what is there now, without adding a second copy" do
      Repo.insert!(%SecretConfig{
        name: "vault-prod",
        plugin_id: "cd.go.secrets.vault",
        configuration: %{"address" => "https://old-vault.test"}
      })

      config = %{
        "secret_configs" => [
          %{
            "name" => "vault-prod",
            "plugin_id" => "cd.go.secrets.vault",
            "configuration" => %{"address" => "https://new-vault.test"}
          }
        ]
      }

      assert :ok = ConfigRestore.restore(config)

      assert [secret] = Repo.all(SecretConfig)
      assert secret.configuration == %{"address" => "https://new-vault.test"}
    end

    test "a configuration without these sections restores nothing and does not fail" do
      assert :ok = ConfigRestore.restore(%{"pipelines" => []})
      assert Repo.all(SecretConfig) == []
    end
  end
end
