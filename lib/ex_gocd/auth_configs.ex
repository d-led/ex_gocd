defmodule ExGoCD.AuthConfigs do
  @moduledoc "Context for authentication provider configurations (LDAP, GitHub OAuth, etc.)."
  import Ecto.Query, warn: false
  alias ExGoCD.AuthConfigs.AuthConfig
  alias ExGoCD.Repo

  def list_configs, do: Repo.all(AuthConfig)
  def get_config!(id), do: Repo.get!(AuthConfig, id)

  @doc """
  Fetches an auth config, or `nil` when no config has that id.

  The id arrives from a path, so it is whatever a caller typed; `Repo.get/2`
  raises `Ecto.Query.CastError` for a word, which turns a mistyped path into a
  500. A word simply names nothing.
  """
  def get_config(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(AuthConfig, uuid)
      :error -> nil
    end
  end

  def create_config(attrs \\ %{}) do
    %AuthConfig{} |> AuthConfig.changeset(attrs) |> Repo.insert()
  end

  def update_config(%AuthConfig{} = config, attrs) do
    config |> AuthConfig.changeset(attrs) |> Repo.update()
  end

  def delete_config(%AuthConfig{} = config), do: Repo.delete(config)
end
