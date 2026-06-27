defmodule ExGoCD.AuthConfigs do
  @moduledoc "Context for authentication provider configurations (LDAP, GitHub OAuth, etc.)."
  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.AuthConfigs.AuthConfig

  def list_configs, do: Repo.all(AuthConfig)
  def get_config!(id), do: Repo.get!(AuthConfig, id)
  def get_config(id), do: Repo.get(AuthConfig, id)

  def create_config(attrs \\ %{}) do
    %AuthConfig{} |> AuthConfig.changeset(attrs) |> Repo.insert()
  end

  def update_config(%AuthConfig{} = config, attrs) do
    config |> AuthConfig.changeset(attrs) |> Repo.update()
  end

  def delete_config(%AuthConfig{} = config), do: Repo.delete(config)
end
