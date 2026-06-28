defmodule ExGoCD.ConfigSnapshotTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.ConfigSnapshot
  alias ExGoCD.ConfigVersion
  alias ExGoCD.Repo

  import Ecto.Query

  setup do
    # Clean up config_versions from previous tests
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

    @tag :skip
    test "secure_variables are encrypted, not plaintext" do
      # Insert a pipeline with a secure variable
      alias ExGoCD.Pipelines
      alias ExGoCD.Repo

      {:ok, pipeline} =
        Pipelines.create_pipeline(%{
          name: "snapshot-test-pipeline",
          group: "test",
          secure_variables: %{"SECRET_KEY" => "my-secret-value"}
        })

      {:ok, v} = ConfigSnapshot.snapshot("test", "encryption check")

      pipelines = v.config_json["pipelines"]
      test_pipeline = Enum.find(pipelines, &(&1["name"] == "snapshot-test-pipeline"))

      assert test_pipeline != nil
      secure = test_pipeline["secure_variables"]
      assert secure != nil

      # Should be AES-encrypted, not plaintext
      secret_val = secure["SECRET_KEY"]
      assert secret_val != nil
      assert String.starts_with?(secret_val, "AES:")
      refute secret_val == "my-secret-value"

      # Cleanup
      Repo.delete(pipeline)
    end

    @tag :skip
    test "cluster profiles encrypt bearer tokens" do
      alias ExGoCD.ClusterProfiles

      {:ok, cluster} =
        ClusterProfiles.create_profile(%{
          name: "snapshot-cluster",
          plugin_id: "cd.go.contrib.kubernetes",
          bearer_token: "k8s-token-secret"
        })

      {:ok, v} = ConfigSnapshot.snapshot("test", "cluster encryption check")

      profiles = v.config_json["cluster_profiles"]
      test_profile = Enum.find(profiles, &(&1["name"] == "snapshot-cluster"))

      assert test_profile != nil
      encrypted = test_profile["encrypted_bearer_token"]
      assert String.starts_with?(encrypted || "", "AES:")
      refute encrypted == "k8s-token-secret"

      # Cleanup
      Repo.delete(cluster)
    end
  end

  describe "ConfigVersion.recent/1" do
    @tag :skip
    test "returns versions newest first" do
      ConfigSnapshot.snapshot("test", "first")
      # Force a second version by changing something
      Repo.insert!(%ConfigVersion{
        config_hash: "different-hash-#{System.unique_integer()}",
        config_json: %{test: true},
        changed_by: "test",
        change_reason: "forced second"
      })

      recent = ConfigVersion.recent(5)
      assert length(recent) >= 2
      ids = Enum.map(recent, & &1.id)
      assert Enum.at(ids, 0) >= Enum.at(ids, 1)
    end
  end
end
