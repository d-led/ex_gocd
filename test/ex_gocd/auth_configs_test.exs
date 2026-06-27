defmodule ExGoCD.AuthConfigsTest do
  use ExGoCD.DataCase
  alias ExGoCD.AuthConfigs

  @valid %{plugin_id: "cd.go.authentication.ldap", properties: %{"ldap_url" => "ldap://example.com"}}

  test "CRUD for auth configs" do
    assert [] = AuthConfigs.list_configs()
    {:ok, config} = AuthConfigs.create_config(@valid)
    assert config.plugin_id == "cd.go.authentication.ldap"

    assert [%{}] = AuthConfigs.list_configs()
    assert %{} = AuthConfigs.get_config!(config.id)

    {:ok, updated} = AuthConfigs.update_config(config, %{plugin_id: "github"})
    assert updated.plugin_id == "github"

    {:ok, _} = AuthConfigs.delete_config(config)
    assert [] = AuthConfigs.list_configs()
  end

  test "validation requires plugin_id" do
    {:error, cs} = AuthConfigs.create_config(%{})
    assert "can't be blank" in errors_on(cs).plugin_id
  end
end
