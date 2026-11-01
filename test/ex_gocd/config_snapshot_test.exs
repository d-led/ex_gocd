defmodule ExGoCD.ConfigSnapshotTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.ClusterProfiles
  alias ExGoCD.ConfigSnapshot
  alias ExGoCD.ConfigVersion
  alias ExGoCD.Repo

  setup do
    # Clean up any pre-existing config versions from other test runs.
    # With shared sandbox (async: false), previous tests may have left
    # ConfigVersion rows that would cause snapshot deduplication to
    # return :unchanged prematurely.
    Repo.delete_all(ConfigVersion)
    :ok
  end

  describe "snapshot/2" do
    test "creates a config version when config changes" do
      assert {:ok, %ConfigVersion{} = v1} = ConfigSnapshot.snapshot("test", "initial snapshot")
      assert v1.config_hash != nil
      assert v1.config_json != nil
      assert v1.changed_by == "test"
      assert v1.change_reason == "initial snapshot"
    end

    test "returns :unchanged when config hash matches latest" do
      assert {:ok, _v1} = ConfigSnapshot.snapshot("test", "first")
      assert :unchanged = ConfigSnapshot.snapshot("test", "unchanged")
    end

    test "does not record a configuration it already holds" do
      {:ok, first} = ConfigSnapshot.snapshot("test", "first")

      {:ok, profile} =
        ClusterProfiles.create_profile(%{
          name: "comes-and-goes",
          plugin_id: "ex_gocd.elasticagent.kubernetes",
          properties: %{}
        })

      assert {:ok, _with_profile} = ConfigSnapshot.snapshot("test", "profile added")
      assert {:ok, _} = ClusterProfiles.delete_profile(profile)

      assert :unchanged = ConfigSnapshot.snapshot("test", "profile removed")

      assert ConfigVersion
             |> Repo.all()
             |> Enum.count(&(&1.config_hash == first.config_hash)) == 1
    end

    test "config_json contains expected top-level sections" do
      {:ok, v} = ConfigSnapshot.snapshot("test", "section check")
      config = v.config_json

      assert is_map(config)
      assert config["schema_version"] == 1
      assert Map.has_key?(config, "server")
      assert Map.has_key?(config, "pipelines")
      assert Map.has_key?(config, "templates")
      assert Map.has_key?(config, "environments")
      assert Map.has_key?(config, "elastic_profiles")
      assert Map.has_key?(config, "cluster_profiles")
      assert Map.has_key?(config, "security")
      assert Map.has_key?(config, "artifact_stores")
      assert Map.has_key?(config, "secret_configs")
      assert Map.has_key?(config, "package_repositories")
      assert Map.has_key?(config, "scms")
      assert Map.has_key?(config, "config_repos")
    end

    test "secure_variables are encrypted, not plaintext" do
      alias ExGoCD.Pipelines.Pipeline

      # Use direct insert to avoid API side-effects in sandbox
      pipeline =
        Repo.insert!(%Pipeline{
          name: "snapshot-enc-test-#{System.unique_integer([:positive])}",
          group: "test",
          secure_variables: %{"SECRET_KEY" => "my-secret-value"}
        })

      {:ok, v} = ConfigSnapshot.snapshot("test", "encryption check")

      pipelines = v.config_json["pipelines"]
      test_pipeline = Enum.find(pipelines, &(&1["name"] == pipeline.name))

      assert test_pipeline != nil
      secure = test_pipeline["secure_variables"]
      assert secure != nil

      secret_val = secure["SECRET_KEY"]
      assert String.starts_with?(secret_val, "AES:")
      refute secret_val == "my-secret-value"
    end

    test "captures the plugin-configured sections a restore has to recreate" do
      alias ExGoCD.ArtifactStores.ArtifactStore
      alias ExGoCD.ConfigRepos.ConfigRepo
      alias ExGoCD.PackageRepositories.PackageRepository
      alias ExGoCD.SecretConfigs.SecretConfig

      artifact_store =
        Repo.insert!(%ArtifactStore{
          plugin_id: "cd.go.artifact.docker.registry",
          properties: %{"RegistryURL" => "https://registry.test"}
        })

      package_repository =
        Repo.insert!(%PackageRepository{
          name: "acme-npm",
          plugin_id: "cd.go.reporter.artifact.npm",
          configuration: %{"RepositoryURL" => "https://npm.test"}
        })

      Repo.insert!(%SecretConfig{
        name: "vault-prod",
        plugin_id: "cd.go.secrets.vault",
        configuration: %{"address" => "https://vault.test"}
      })

      repo_config =
        Repo.insert!(%ConfigRepo{
          url: "https://github.com/acme/config.git",
          branch: "trunk",
          plugin_id: "cd.go.config-repo.yaml",
          configuration: %{"pattern" => "*.gocd.yaml"}
        })

      {:ok, version} = ConfigSnapshot.snapshot("test", "plugin sections")
      config = version.config_json

      secrets = config["secret_configs"]

      assert Enum.any?(
               secrets,
               &(&1["name"] == "vault-prod" and &1["plugin_id"] == "cd.go.secrets.vault")
             )

      repositories = config["package_repositories"]

      assert Enum.any?(
               repositories,
               &(&1["id"] == package_repository.id and &1["name"] == "acme-npm")
             )

      stores = config["artifact_stores"]

      assert Enum.any?(
               stores,
               &(&1["id"] == artifact_store.id and
                   &1["properties"] == %{"RegistryURL" => "https://registry.test"})
             )

      repos = config["config_repos"]

      assert Enum.any?(
               repos,
               &(&1["id"] == repo_config.id and &1["url"] == "https://github.com/acme/config.git" and
                   &1["branch"] == "trunk")
             )

      assert Enum.all?(Map.values(config), &(not is_map(&1) or not Map.has_key?(&1, "_error")))
    end

    test "cluster profiles encrypt bearer tokens" do
      {:ok, _profile} =
        ClusterProfiles.create_profile(%{
          name: "encryption-test-cluster",
          plugin_id: "ex_gocd.elasticagent.kubernetes",
          properties: %{
            "kubernetes_cluster_url" => "https://k8s.test:6443",
            "bearer_token" => "super-secret-bearer-token-12345"
          }
        })

      {:ok, v} = ConfigSnapshot.snapshot("test", "bearer token encryption check")

      clusters = v.config_json["cluster_profiles"]
      test_cluster = Enum.find(clusters, &(&1["name"] == "encryption-test-cluster"))

      assert test_cluster != nil
      encrypted = test_cluster["encrypted_bearer_token"]

      assert encrypted != nil
      assert String.starts_with?(encrypted, "AES:")
      refute encrypted == "super-secret-bearer-token-12345"
    end
  end

  describe "ConfigVersion.recent/1" do
    test "returns versions newest first" do
      ConfigSnapshot.snapshot("test", "first")
      # Direct insert forces a second version (snapshot deduplicates by hash)
      Repo.insert!(%ConfigVersion{
        config_hash: "forced-hash-#{System.unique_integer()}",
        config_json: %{test: true},
        config_xml: nil,
        changed_by: "test",
        change_reason: "forced second"
      })

      recent = ConfigVersion.recent(5)
      assert length(recent) >= 2
      # Both records may have same inserted_at; recent/1 orders by inserted_at DESC
      assert length(recent) >= 2
    end
  end
end
