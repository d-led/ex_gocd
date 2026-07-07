defmodule ExGoCD.JWT do
  @moduledoc """
  JWT token generation and verification for API access tokens.

  Tokens are self-contained JWTs signed with the application secret.
  Revocation is tracked via the `personal_access_tokens` table using the
  token's `jti` (JWT ID) claim.

  GoCD compatibility: mirrors the AccessToken model's role (long-lived
  API tokens) but uses standard JWT instead of salted SHA256 hashes.
  """

  @type claims :: %{
          required(String.t()) => String.t() | number() | list(String.t())
        }

  # ── Public API ──────────────────────────────────────────────────────────

  @doc """
  Generates a signed JWT for the given user.

  Returns the token string and the `jti` claim used for revocation tracking.
  """
  @spec generate(map()) :: {:ok, String.t(), String.t()} | {:error, any()}
  def generate(%{id: user_id, username: username, roles: roles}) do
    now = current_timestamp()
    jti = generate_jti()

    claims = %{
      "sub" => to_string(user_id),
      "username" => username,
      "roles" => roles,
      "iat" => now,
      "jti" => jti
    }

    case Joken.encode_and_sign(claims, signer()) do
      {:ok, token, _claims} -> {:ok, token, jti}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Verifies a JWT token string.

  Returns `{:ok, claims}` if the token is valid and signed,
  or `{:error, reason}` otherwise.
  """
  @spec verify(String.t()) :: {:ok, claims()} | {:error, atom()}
  def verify(token) when is_binary(token) do
    Joken.verify(token, signer())
  end

  @doc """
  Returns the secret used for JWT signing.

  Priority: `EX_GOCD_JWT_SECRET` env var → app's `secret_key_base`.
  """
  @spec secret() :: String.t()
  def secret do
    System.get_env("EX_GOCD_JWT_SECRET") ||
      Application.get_env(:ex_gocd, ExGoCDWeb.Endpoint)[:secret_key_base] ||
      raise("JWT secret not configured — set EX_GOCD_JWT_SECRET or SECRET_KEY_BASE")
  end

  # ── Private ─────────────────────────────────────────────────────────────

  defp signer do
    # Derive a 32-byte key from the secret for HS256 (requires ≥256-bit key)
    key = :crypto.hash(:sha256, secret())
    Joken.Signer.create("HS256", key)
  end

  defp current_timestamp, do: System.system_time(:second)

  defp generate_jti do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
