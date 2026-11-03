defmodule ExGoCD.Agents.Token do
  @moduledoc """
  The credential an agent presents as `Authorization` on every remoting call.

  GoCD hands each agent a token when it registers. This server derives it from
  the agent's uuid and a secret only the server holds, so the same agent always
  receives the same token — an agent that lost its copy can ask again — and no
  token is stored anywhere.

  `EX_GOCD_DEMO_COOKIE`, when set, is the token for every agent: the Go agent
  and the HTTP test agent both use it as a shared credential for the docker
  demo, and it is accepted here for that reason.
  """

  @doc "The token this server accepts from `uuid`."
  @spec for_agent(String.t()) :: String.t()
  def for_agent(uuid) when is_binary(uuid) do
    case demo_cookie() do
      nil -> derived(uuid)
      cookie -> cookie
    end
  end

  @doc """
  Whether `token` is one this server accepts from `uuid`.

  Answers false for a missing token rather than treating it as a match: a
  request without a credential is not an agent.
  """
  @spec valid?(String.t(), String.t() | nil) :: boolean()
  def valid?(uuid, token) when is_binary(uuid) and is_binary(token) and token != "" do
    Plug.Crypto.secure_compare(token, for_agent(uuid))
  end

  def valid?(_uuid, _token), do: false

  @spec derived(String.t()) :: String.t()
  defp derived(uuid) do
    :crypto.mac(:hmac, :sha256, secret(), "agent:" <> uuid)
    |> Base.url_encode64(padding: false)
  end

  @spec demo_cookie() :: String.t() | nil
  defp demo_cookie do
    case System.get_env("EX_GOCD_DEMO_COOKIE") do
      nil -> nil
      cookie -> if String.trim(cookie) == "", do: nil, else: String.trim(cookie)
    end
  end

  # The endpoint's own secret: it already exists on every server, release or
  # not, and is exactly the kind of value that must not leave the machine.
  @spec secret() :: String.t()
  defp secret do
    Application.get_env(:ex_gocd, :agent_token_secret) ||
      Application.fetch_env!(:ex_gocd, ExGoCDWeb.Endpoint)[:secret_key_base]
  end
end
