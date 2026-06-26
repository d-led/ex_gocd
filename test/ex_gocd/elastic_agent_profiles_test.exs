defmodule ExGoCD.ElasticAgentProfilesTest do
  use ExGoCD.DataCase

  alias ExGoCD.ElasticAgentProfiles
  alias ExGoCD.ElasticAgentProfiles.ElasticAgentProfile

  describe "elastic agent profiles" do
    @valid_attrs %{plugin_id: "cd.go.contrib.elasticagent.kubernetes", properties: %{"Image" => "alpine"}}
    @update_attrs %{properties: %{"Image" => "ubuntu", "MaxMemory" => "512Mi"}}

    test "list_profiles/0 returns all profiles" do
      assert [] = ElasticAgentProfiles.list_profiles()

      {:ok, profile} = ElasticAgentProfiles.create_profile(@valid_attrs)
      assert [%ElasticAgentProfile{}] = ElasticAgentProfiles.list_profiles()
      assert profile.plugin_id == "cd.go.contrib.elasticagent.kubernetes"
    end

    test "get_profile!/1 returns the profile" do
      {:ok, profile} = ElasticAgentProfiles.create_profile(@valid_attrs)
      found = ElasticAgentProfiles.get_profile!(profile.id)
      assert found.plugin_id == "cd.go.contrib.elasticagent.kubernetes"
    end

    test "create_profile/1 with valid data creates a profile" do
      {:ok, profile} = ElasticAgentProfiles.create_profile(@valid_attrs)
      assert profile.plugin_id == "cd.go.contrib.elasticagent.kubernetes"
      assert profile.properties == %{"Image" => "alpine"}
    end

    test "create_profile/1 with invalid data returns error" do
      {:error, changeset} = ElasticAgentProfiles.create_profile(%{})
      assert "can't be blank" in errors_on(changeset).plugin_id
    end

    test "update_profile/2 updates the profile" do
      {:ok, profile} = ElasticAgentProfiles.create_profile(@valid_attrs)
      {:ok, updated} = ElasticAgentProfiles.update_profile(profile, @update_attrs)
      assert updated.properties == %{"Image" => "ubuntu", "MaxMemory" => "512Mi"}
    end

    test "delete_profile/1 deletes the profile" do
      {:ok, profile} = ElasticAgentProfiles.create_profile(@valid_attrs)
      {:ok, _} = ElasticAgentProfiles.delete_profile(profile)
      assert [] = ElasticAgentProfiles.list_profiles()
    end

    test "list_by_plugin/1 filters by plugin_id" do
      ElasticAgentProfiles.create_profile(%{plugin_id: "k8s", properties: %{}})
      ElasticAgentProfiles.create_profile(%{plugin_id: "docker", properties: %{}})
      assert length(ElasticAgentProfiles.list_by_plugin("k8s")) == 1
    end
  end
end
