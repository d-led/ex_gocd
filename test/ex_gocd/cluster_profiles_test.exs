defmodule ExGoCD.ClusterProfilesTest do
  use ExGoCD.DataCase

  alias ExGoCD.ClusterProfiles
  alias ExGoCD.ClusterProfiles.ClusterProfile

  describe "cluster profiles" do
    @valid_attrs %{
      name: "test-cluster",
      plugin_id: "ex_gocd.elasticagent.kubernetes",
      properties: %{"kubernetes_cluster_url" => "https://k8s.test:6443"}
    }
    @update_attrs %{
      properties: %{
        "kubernetes_cluster_url" => "https://new-k8s.example.com",
        "namespace" => "gocd-agents"
      }
    }

    test "list_profiles/0 returns all profiles" do
      assert [] = ClusterProfiles.list_profiles()
      {:ok, _} = ClusterProfiles.create_profile(@valid_attrs)
      assert [%ClusterProfile{}] = ClusterProfiles.list_profiles()
    end

    test "get_profile!/1 returns the profile" do
      {:ok, profile} = ClusterProfiles.create_profile(@valid_attrs)
      found = ClusterProfiles.get_profile!(profile.id)
      assert found.plugin_id == @valid_attrs.plugin_id
    end

    test "create_profile/1 with valid data creates a profile" do
      {:ok, profile} = ClusterProfiles.create_profile(@valid_attrs)
      assert profile.plugin_id == @valid_attrs.plugin_id
      assert profile.properties == @valid_attrs.properties
    end

    test "create_profile/1 with invalid data returns error" do
      {:error, changeset} = ClusterProfiles.create_profile(%{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "update_profile/2 updates the profile" do
      {:ok, profile} = ClusterProfiles.create_profile(@valid_attrs)
      {:ok, updated} = ClusterProfiles.update_profile(profile, @update_attrs)
      assert updated.properties == @update_attrs.properties
    end

    test "delete_profile/1 deletes the profile" do
      {:ok, profile} = ClusterProfiles.create_profile(@valid_attrs)
      {:ok, _} = ClusterProfiles.delete_profile(profile)
      assert [] = ClusterProfiles.list_profiles()
    end

    test "list_by_plugin/1 filters by plugin_id" do
      ClusterProfiles.create_profile(%{name: "k8s-cluster", plugin_id: "k8s", properties: %{}})

      ClusterProfiles.create_profile(%{
        name: "docker-cluster",
        plugin_id: "docker",
        properties: %{}
      })

      assert length(ClusterProfiles.list_by_plugin("k8s")) == 1
    end
  end

  describe "maybe_auto_seed_k3s/0" do
    test "returns :no_k3s when k3s is not available" do
      assert ClusterProfiles.maybe_auto_seed_k3s() == :no_k3s
    end

    test "returns :ok when k3s-local profile already exists (idempotent)" do
      {:ok, _} =
        ClusterProfiles.create_profile(%{
          name: "k3s-local",
          plugin_id: "ex_gocd.elasticagent.kubernetes",
          properties: %{"kubernetes_cluster_url" => "https://localhost:6443"}
        })

      assert ClusterProfiles.maybe_auto_seed_k3s() == :ok
    end
  end
end
