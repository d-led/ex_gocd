defmodule ExGoCD.Mcp.OAuthCode do
  @moduledoc """
  A one-time authorization code, stored as a hash.

  The code itself exists only in the redirect the browser follows; what is kept
  is its SHA-256, so a copy of the database is not a copy of the ability to
  exchange it. A code is single-use (`used_at`), short-lived (`expires_at`), and
  bound to the client, the redirect URI, and the PKCE challenge it was issued
  with — every one of which the exchange checks, because a code that could be
  replayed against another client or another verifier is not a code.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Accounts.User

  @type t :: %__MODULE__{
          id: integer() | nil,
          client_id: String.t() | nil,
          user_id: integer() | nil,
          redirect_uri: String.t() | nil,
          code_hash: String.t() | nil,
          code_challenge: String.t() | nil,
          code_challenge_method: String.t(),
          scope: String.t() | nil,
          expires_at: DateTime.t() | nil,
          used_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "mcp_oauth_codes" do
    field :client_id, :string
    field :redirect_uri, :string
    field :code_hash, :string
    field :code_challenge, :string
    field :code_challenge_method, :string, default: "S256"
    field :scope, :string
    field :expires_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec

    belongs_to :user, User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "An issued code."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(code, attrs) do
    code
    |> cast(attrs, [
      :client_id,
      :user_id,
      :redirect_uri,
      :code_hash,
      :code_challenge,
      :code_challenge_method,
      :scope,
      :expires_at
    ])
    |> validate_required([
      :client_id,
      :user_id,
      :redirect_uri,
      :code_hash,
      :code_challenge,
      :expires_at
    ])
    |> unique_constraint(:code_hash)
  end
end
