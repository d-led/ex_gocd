defmodule ExGoCD.ClusterProfilesTest do
  use ExGoCD.DataCase

  alias ExGoCD.ClusterProfiles
  alias ExGoCD.ClusterProfiles.ClusterProfile

  describe "cluster profiles" do
    @valid_attrs %{
      plugin_id: "cd.go.contrib.elasticagent.kubernetes",
      properties: %{"go_server_url" => "https://gocd.example.com"}
    }
    @update_attrs %{
      properties: %{
        "go_server_url" => "https://new.example.com",
        "kubernetes_cluster_url" => "https://k8s.example.com"
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
      assert "can't be blank" in errors_on(changeset).plugin_id
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
      ClusterProfiles.create_profile(%{plugin_id: "k8s", properties: %{}})
      ClusterProfiles.create_profile(%{plugin_id: "docker", properties: %{}})
      assert length(ClusterProfiles.list_by_plugin("k8s")) == 1
    end
  end
end
