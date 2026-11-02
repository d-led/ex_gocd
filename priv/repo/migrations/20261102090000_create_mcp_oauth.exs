defmodule ExGoCD.Repo.Migrations.CreateMcpOauth do
  @moduledoc """
  The MCP authorization round trip needs two small tables: the clients that
  registered themselves, and the one-time authorization codes they traded.

  No access tokens are stored here. A token this flow issues is a GoCD personal
  access token (`personal_access_tokens`), so it is revoked the way every other
  GoCD token is.
  """
  use Ecto.Migration

  def change do
    create table(:mcp_oauth_clients) do
      add :client_id, :string, null: false
      add :client_name, :string
      add :redirect_uris, {:array, :string}, null: false, default: []
      add :token_endpoint_auth_method, :string, null: false, default: "none"

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:mcp_oauth_clients, [:client_id])

    create table(:mcp_oauth_codes) do
      add :client_id, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :redirect_uri, :string, null: false
      add :code_hash, :string, null: false
      add :code_challenge, :string, null: false
      add :code_challenge_method, :string, null: false, default: "S256"
      add :scope, :string
      add :expires_at, :utc_datetime_usec, null: false
      add :used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:mcp_oauth_codes, [:code_hash])
    create index(:mcp_oauth_codes, [:client_id])
  end
end
