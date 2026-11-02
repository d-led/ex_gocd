defmodule ExGoCD.Mcp.Identity do
  @moduledoc """
  Who a request is.

  Four credentials are accepted, in this order, because they are the ones the
  server's other surfaces already accept and an MCP client should not have to
  learn a fifth:

    1. `Authorization: Bearer <token>` — a GoCD personal access token, which is
       also what the OAuth round trip (`ExGoCD.Mcp.OAuth`) mints;
    2. `Authorization: Basic base64(username:token)` — the token is the
       credential and the username has to agree with the account it belongs to.
       There is no password form: signing in to this server identifies a user,
       it does not authenticate one against a secret, and no password is stored;
    3. the session cookie — a browser, or an identity a reverse proxy wrote into
       a header. `ExGoCDWeb.Plugs.AuthHeaderPlug` turns oauth2-proxy's
       `X-Forwarded-User` (and its `X-Auth-Request-*` cousins) into a session
       before this module looks;
    4. nothing at all — the guest, which is an administrator while the server is
       in open mode (no administrator configured yet) and a viewer afterwards,
       exactly as on the JSON API.

  A credential that is *presented* and wrong is a refusal, never a fallback to
  the guest: answering as somebody else is how a misconfigured client spends an
  hour wondering why its writes vanished.

  `require_auth?/0` closes the remaining hole for a deployment reachable from
  the internet. With it on, "nothing at all" is a refusal carrying the MCP
  authorization challenge, so a client that supports remote servers starts the
  OAuth flow by itself. It is off by default because the JSON API and the pages
  it shares a server with already let a guest read.
  """

  import Plug.Conn

  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.User

  @type error :: :unauthorized | :invalid_token | :invalid_credentials | :account_disabled

  @doc """
  The identity behind a request.

  Returns `{:ok, user}` when the request may proceed — including the guest of a
  server that does not insist on credentials — and `{:error, reason}` when it
  may not.
  """
  @spec identity(Plug.Conn.t()) :: {:ok, User.t()} | {:error, error()}
  def identity(conn) do
    with :none <- bearer(conn),
         :none <- basic(conn),
         :none <- session(conn) do
      if require_auth?(), do: {:error, :unauthorized}, else: {:ok, guest()}
    end
  end

  @doc """
  The browser identity, for the OAuth step that needs a person to consent.

  A bearer token cannot approve a client: consent is a decision a human makes in
  a browser, and the session is where that human is remembered. Returns `nil`
  when this request carries no signed-in user.
  """
  @spec session_user(Plug.Conn.t()) :: User.t() | nil
  def session_user(conn) do
    case get_session(conn, "username") do
      nil -> nil
      _username -> conn |> get_session() |> Accounts.get_current_user() |> active_user()
    end
  end

  @doc "Whether this deployment refuses requests that carry no credential."
  @spec require_auth?() :: boolean()
  def require_auth? do
    System.get_env("EX_GOCD_MCP_REQUIRE_AUTH") == "true" or
      Application.get_env(:ex_gocd, :mcp_require_auth, false)
  end

  defp guest, do: Accounts.get_current_user(%{})

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> verify_token(String.trim(token))
      _other -> :none
    end
  end

  defp basic(conn) do
    case get_req_header(conn, "authorization") do
      ["Basic " <> encoded] -> basic_credentials(String.trim(encoded))
      _other -> :none
    end
  end

  # GoCD's basic form is `username:access-token`: the token is the credential,
  # the username only has to agree with the account it belongs to.
  defp basic_credentials(encoded) do
    with {:ok, decoded} <- Base.decode64(encoded),
         [username, token] <- String.split(decoded, ":", parts: 2),
         {:ok, %User{} = user} <- verify_token(token),
         :ok <- same_user(username, user) do
      {:ok, user}
    else
      _other -> {:error, :invalid_credentials}
    end
  end

  defp same_user(username, %User{username: username}), do: :ok
  defp same_user(_username, _user), do: {:error, :invalid_credentials}

  defp verify_token(token) do
    case Accounts.verify_access_token(token) do
      {:ok, user} -> active(user)
      {:error, _reason} -> {:error, :invalid_token}
    end
  end

  defp session(conn) do
    case session_user(conn) do
      nil -> :none
      user -> {:ok, user}
    end
  end

  defp active(%User{status: "Active"} = user), do: {:ok, user}
  defp active(_user), do: {:error, :account_disabled}

  defp active_user(%User{status: "Active"} = user), do: user
  defp active_user(_user), do: nil
end
