defmodule ExGoCD.Mcp.OAuthClient do
  @moduledoc """
  A client that registered itself for the MCP authorization round trip.

  Public clients only: the registration says `token_endpoint_auth_method: none`,
  which is why the code exchange insists on PKCE. The redirect URIs are the
  allow-list an authorization request is checked against — a redirect the client
  did not register is never followed, because following it would be handing a
  code to whoever asked.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          client_id: String.t() | nil,
          client_name: String.t() | nil,
          redirect_uris: [String.t()],
          token_endpoint_auth_method: String.t(),
          inserted_at: DateTime.t() | nil
        }

  schema "mcp_oauth_clients" do
    field :client_id, :string
    field :client_name, :string
    field :redirect_uris, {:array, :string}, default: []
    field :token_endpoint_auth_method, :string, default: "none"

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "A registration from the registration endpoint."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(client, attrs) do
    client
    |> cast(attrs, [:client_id, :client_name, :redirect_uris, :token_endpoint_auth_method])
    |> validate_required([:client_id, :redirect_uris])
    |> unique_constraint(:client_id)
  end

  @doc "Whether a redirect URI is one this client registered."
  @spec allows_redirect?(t(), String.t()) :: boolean()
  def allows_redirect?(%__MODULE__{redirect_uris: uris}, redirect_uri)
      when is_binary(redirect_uri) do
    redirect_uri in (uris || [])
  end

  def allows_redirect?(_client, _redirect_uri), do: false
end
