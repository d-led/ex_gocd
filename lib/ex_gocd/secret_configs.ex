defmodule ExGoCD.SecretConfigs do
  @moduledoc """
  Context for secret configurations (e.g., HashiCorp Vault, AWS Secrets Manager).
  """

  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.SecretConfigs.SecretConfig

  def list_configs, do: Repo.all(SecretConfig)
  def get_config!(id), do: Repo.get!(SecretConfig, id)
  def get_config(id), do: Repo.get(SecretConfig, id)

  def create_config(attrs \\ %{}) do
    %SecretConfig{}
    |> SecretConfig.changeset(attrs)
    |> Repo.insert()
  end

  def update_config(%SecretConfig{} = config, attrs) do
    config |> SecretConfig.changeset(attrs) |> Repo.update()
  end

  def delete_config(%SecretConfig{} = config), do: Repo.delete(config)

  def list_by_plugin(plugin_id) do
    Repo.all(from c in SecretConfig, where: c.plugin_id == ^plugin_id)
  end
end
