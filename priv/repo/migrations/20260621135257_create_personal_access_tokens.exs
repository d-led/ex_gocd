defmodule ExGoCD.Repo.Migrations.CreatePersonalAccessTokens do
  use Ecto.Migration

  def change do
    create table(:personal_access_tokens) do
      add :description, :text, null: false
      add :token_hash, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :last_used_at, :utc_datetime
      add :revoked, :boolean, default: false, null: false
      add :revoked_at, :utc_datetime
      add :revoked_by, :string
      add :revoke_cause, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:personal_access_tokens, [:token_hash])
    create index(:personal_access_tokens, [:user_id])
  end
end
