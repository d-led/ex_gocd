defmodule ExGoCD.ElasticAgentProfilesTest do
  use ExGoCD.DataCase

  alias ExGoCD.ElasticAgentProfiles
  alias ExGoCD.ElasticAgentProfiles.ElasticAgentProfile
  alias ExGoCD.ClusterProfiles

  describe "elastic agent profiles" do
    @cluster_id Ecto.UUID.generate()

    setup do
      # Create a prerequisite cluster profile
      {:ok, cluster} =
        ClusterProfiles.create_profile(%{
          name: "test-cluster",
          plugin_id: "cd.go.contrib.elasticagent.kubernetes",
          properties: %{"kubernetes_cluster_url" => "https://k8s.test:6443"}
        })

      %{cluster_id: cluster.id}
    end

    @valid_attrs %{
      name: "test-agent",
      plugin_id: "cd.go.contrib.elasticagent.kubernetes",
      properties: %{"Image" => "alpine"}
    }
    @update_attrs %{properties: %{"Image" => "ubuntu", "MaxMemory" => "512Mi"}}

    test "list_profiles/0 returns all profiles", %{cluster_id: cid} do
      assert [] = ElasticAgentProfiles.list_profiles()

      {:ok, profile} =
        ElasticAgentProfiles.create_profile(Map.put(@valid_attrs, :cluster_profile_id, cid))

      assert [%ElasticAgentProfile{}] = ElasticAgentProfiles.list_profiles()
      assert profile.plugin_id == "cd.go.contrib.elasticagent.kubernetes"
    end

    test "get_profile!/1 returns the profile", %{cluster_id: cid} do
      {:ok, profile} =
        ElasticAgentProfiles.create_profile(Map.put(@valid_attrs, :cluster_profile_id, cid))

      found = ElasticAgentProfiles.get_profile!(profile.id)
      assert found.plugin_id == "cd.go.contrib.elasticagent.kubernetes"
    end

    test "create_profile/1 with valid data creates a profile", %{cluster_id: cid} do
      {:ok, profile} =
        ElasticAgentProfiles.create_profile(Map.put(@valid_attrs, :cluster_profile_id, cid))

      assert profile.plugin_id == "cd.go.contrib.elasticagent.kubernetes"
      assert profile.properties == %{"Image" => "alpine"}
    end

    test "create_profile/1 with invalid data returns error" do
      {:error, changeset} = ElasticAgentProfiles.create_profile(%{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "update_profile/2 updates the profile", %{cluster_id: cid} do
      {:ok, profile} =
        ElasticAgentProfiles.create_profile(Map.put(@valid_attrs, :cluster_profile_id, cid))

      {:ok, updated} = ElasticAgentProfiles.update_profile(profile, @update_attrs)
      assert updated.properties == %{"Image" => "ubuntu", "MaxMemory" => "512Mi"}
    end

    test "delete_profile/1 deletes the profile", %{cluster_id: cid} do
      {:ok, profile} =
        ElasticAgentProfiles.create_profile(Map.put(@valid_attrs, :cluster_profile_id, cid))

      {:ok, _} = ElasticAgentProfiles.delete_profile(profile)
      assert [] = ElasticAgentProfiles.list_profiles()
    end

    test "list_by_plugin/1 filters by plugin_id", %{cluster_id: cid} do
      ElasticAgentProfiles.create_profile(%{
        name: "k8s-agent",
        plugin_id: "k8s",
        cluster_profile_id: cid,
        properties: %{}
      })

      ElasticAgentProfiles.create_profile(%{
        name: "docker-agent",
        plugin_id: "docker",
        cluster_profile_id: cid,
        properties: %{}
      })

      assert length(ElasticAgentProfiles.list_by_plugin("k8s")) == 1
    end
  end
end
