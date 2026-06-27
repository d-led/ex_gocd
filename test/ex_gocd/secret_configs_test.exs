defmodule ExGoCD.SecretConfigsTest do
  use ExGoCD.DataCase
  alias ExGoCD.SecretConfigs

  @valid %{name: "vault-prod", plugin_id: "hashicorp-vault", configuration: %{"vault_url" => "https://vault.example.com"}, description: "Production Vault"}

  test "CRUD for secret configs" do
    assert [] = SecretConfigs.list_configs()

    {:ok, config} = SecretConfigs.create_config(@valid)
    assert config.name == "vault-prod"
    assert config.description == "Production Vault"

    assert [%{}] = SecretConfigs.list_configs()
    assert %{} = SecretConfigs.get_config!(config.id)

    {:ok, updated} = SecretConfigs.update_config(config, %{name: "vault-staging"})
    assert updated.name == "vault-staging"

    {:ok, _} = SecretConfigs.delete_config(config)
    assert [] = SecretConfigs.list_configs()
  end

  test "validation requires name and plugin_id" do
    {:error, cs} = SecretConfigs.create_config(%{})
    assert "can't be blank" in errors_on(cs).name
    assert "can't be blank" in errors_on(cs).plugin_id
  end

  test "list_by_plugin filters" do
    SecretConfigs.create_config(%{name: "a", plugin_id: "vault", configuration: %{}})
    SecretConfigs.create_config(%{name: "b", plugin_id: "aws", configuration: %{}})
    assert length(SecretConfigs.list_by_plugin("vault")) == 1
  end
end
