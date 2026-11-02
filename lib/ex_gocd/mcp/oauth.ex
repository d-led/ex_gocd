defmodule ExGoCD.Mcp.OAuth do
  @moduledoc """
  The MCP authorization round trip: a client registers itself, the reader
  approves it in a browser, and the token that comes back is a GoCD access
  token.

  That last part is the whole design. `ExGoCD.Accounts.create_user_token/2`
  mints the token and `ExGoCD.Accounts.verify_access_token/1` checks it, so a
  token from this flow is worth exactly what a token pasted from the access
  tokens page is worth: the same `ExGoCD.Mcp.Identity` accepts it, the same
  "revoke" button ends it, and disabling the user stops the next call. This
  module stores no secret of its own.

  What it does store is what a client needs to be *told apart*: the
  registration (a public client — no secret, PKCE only) and the one-time
  authorization codes, as hashes, for five minutes. A code is bound to the
  client, the redirect URI and the PKCE challenge it was issued for, and it is
  consumed by a conditional update, so the same code cannot be traded twice even
  by two requests at once.
  """

  import Ecto.Query

  alias ExGoCD.{Accounts, Repo}
  alias ExGoCD.Mcp.{OAuthClient, OAuthCode}

  @scopes ["mcp"]
  @code_lifetime_seconds 300

  @type exchange_error ::
          :unknown_code
          | :client_mismatch
          | :redirect_mismatch
          | :expired
          | :bad_verifier
          | :already_used

  @doc "The scopes this server advertises. It does not enforce one: a token sees what its reader sees."
  @spec scopes() :: [String.t()]
  def scopes, do: @scopes

  @doc "How long an authorization code is good for."
  @spec code_lifetime_seconds() :: pos_integer()
  def code_lifetime_seconds, do: @code_lifetime_seconds

  @doc """
  Registers a client from the registration endpoint's JSON.

  Public clients only, so there is no secret to hand back and no way to
  authenticate one later; the redirect URIs are the allow-list.
  """
  @spec register_client(map()) ::
          {:ok, OAuthClient.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def register_client(attrs) when is_map(attrs) do
    with {:ok, redirect_uris} <- redirect_uris(attrs) do
      %OAuthClient{}
      |> OAuthClient.changeset(%{
        client_id: "gocd_" <> random(18),
        client_name: client_name(attrs),
        redirect_uris: redirect_uris,
        token_endpoint_auth_method: "none"
      })
      |> Repo.insert()
    end
  end

  @doc "The client behind a `client_id`, or nil."
  @spec get_client(term()) :: OAuthClient.t() | nil
  def get_client(client_id) when is_binary(client_id),
    do: Repo.get_by(OAuthClient, client_id: client_id)

  def get_client(_client_id), do: nil

  @doc """
  Issues a one-time code for an approved client.

  Returns the code itself — which is only ever handed to the browser in a
  redirect — not the row.
  """
  @spec issue_code(OAuthClient.t(), Accounts.User.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  def issue_code(
        %OAuthClient{} = client,
        %Accounts.User{} = user,
        redirect_uri,
        code_challenge,
        scope
      ) do
    code = random(32)

    %OAuthCode{}
    |> OAuthCode.changeset(%{
      client_id: client.client_id,
      user_id: user.id,
      redirect_uri: redirect_uri,
      code_hash: hash(code),
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      scope: scope,
      expires_at: DateTime.add(DateTime.utc_now(), @code_lifetime_seconds, :second)
    })
    |> Repo.insert()
    |> case do
      {:ok, _row} -> {:ok, code}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Trades a code for its user.

  Every check the code was issued under is made again here, and the code is
  consumed only when they all pass — a mistyped verifier must not burn the
  reader's approval.
  """
  @spec exchange(OAuthClient.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, %{user: Accounts.User.t(), client: OAuthClient.t()}} | {:error, exchange_error()}
  def exchange(%OAuthClient{} = client, redirect_uri, code, verifier) do
    with {:ok, row} <- find_code(code),
         :ok <- same_client(client, row),
         :ok <- same_redirect(redirect_uri, row),
         :ok <- unexpired(row),
         :ok <- verifier_matches(verifier, row),
         :ok <- consume(row) do
      {:ok, %{user: Repo.preload(row, :user).user, client: client}}
    end
  end

  @doc """
  Mints the access token for an approved client.

  The description is what the access tokens page shows, so a reader can tell
  which client a token belongs to before revoking it.
  """
  @spec mint_access_token(OAuthClient.t(), Accounts.User.t()) ::
          {:ok, String.t()} | {:error, term()}
  def mint_access_token(%OAuthClient{} = client, %Accounts.User{id: user_id}) do
    description = "MCP client: " <> (client.client_name || client.client_id)

    case Accounts.create_user_token(user_id, String.slice(description, 0, 120)) do
      {:ok, token} -> {:ok, token.token}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── the checks ─────────────────────────────────────────────────────

  defp find_code(code) when is_binary(code) and code != "" do
    case Repo.get_by(OAuthCode, code_hash: hash(code)) do
      nil -> {:error, :unknown_code}
      row -> {:ok, row}
    end
  end

  defp find_code(_code), do: {:error, :unknown_code}

  defp same_client(%OAuthClient{client_id: client_id}, %OAuthCode{client_id: client_id}), do: :ok
  defp same_client(_client, _row), do: {:error, :client_mismatch}

  defp same_redirect(redirect_uri, %OAuthCode{redirect_uri: redirect_uri}), do: :ok
  defp same_redirect(_redirect_uri, _row), do: {:error, :redirect_mismatch}

  defp unexpired(%OAuthCode{expires_at: expires_at}) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt, do: :ok, else: {:error, :expired}
  end

  defp verifier_matches(verifier, %OAuthCode{code_challenge: challenge})
       when is_binary(verifier) and is_binary(challenge) do
    computed = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    if Plug.Crypto.secure_compare(computed, challenge), do: :ok, else: {:error, :bad_verifier}
  end

  defp verifier_matches(_verifier, _row), do: {:error, :bad_verifier}

  defp consume(%OAuthCode{id: id}) do
    {count, _rows} =
      Repo.update_all(
        from(code in OAuthCode, where: code.id == ^id and is_nil(code.used_at)),
        set: [used_at: DateTime.utc_now()]
      )

    if count == 1, do: :ok, else: {:error, :already_used}
  end

  # ── values ─────────────────────────────────────────────────────────

  defp redirect_uris(%{"redirect_uris" => uris}) when is_list(uris) and uris != [] do
    if Enum.all?(uris, &valid_redirect_uri?/1) do
      {:ok, uris}
    else
      {:error, "Every `redirect_uris` entry must be an absolute http(s) URI without a fragment."}
    end
  end

  defp redirect_uris(_attrs), do: {:error, "`redirect_uris` must be a non-empty list."}

  # RFC 8252 lets a native client use a loopback `http` redirect; anything else
  # in the wild is `https`.
  defp valid_redirect_uri?(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{scheme: scheme, host: host, fragment: nil} when scheme in ["http", "https"] ->
        is_binary(host) and host != ""

      _else ->
        false
    end
  end

  defp valid_redirect_uri?(_uri), do: false

  defp client_name(attrs) do
    case attrs["client_name"] do
      name when is_binary(name) -> name |> String.trim() |> String.slice(0, 120) |> blank_to_nil()
      _other -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(name), do: name

  defp random(bytes), do: Base.url_encode64(:crypto.strong_rand_bytes(bytes), padding: false)

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
