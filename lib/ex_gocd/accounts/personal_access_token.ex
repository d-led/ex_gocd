defmodule ExGoCD.Accounts.PersonalAccessToken do
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Accounts.User

  @type t :: %__MODULE__{
          id: integer() | nil,
          description: String.t() | nil,
          user_id: integer() | nil,
          token_hash: String.t() | nil,
          last_used_at: DateTime.t() | nil,
          revoked: boolean() | nil,
          revoked_at: DateTime.t() | nil,
          revoked_by: String.t() | nil,
          revoke_cause: String.t() | nil,
          token: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "personal_access_tokens" do
    field :description, :string
    field :token_hash, :string
    field :last_used_at, :utc_datetime
    field :revoked, :boolean, default: false
    field :revoked_at, :utc_datetime
    field :revoked_by, :string
    field :revoke_cause, :string

    # Virtual field to return plain-text token only immediately upon creation
    field :token, :string, virtual: true

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a personal access token.
  """
  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :description,
      :user_id,
      :token_hash,
      :last_used_at,
      :revoked,
      :revoked_at,
      :revoked_by,
      :revoke_cause
    ])
    |> validate_required([:description, :user_id, :token_hash])
    |> unique_constraint(:token_hash)
  end
end
