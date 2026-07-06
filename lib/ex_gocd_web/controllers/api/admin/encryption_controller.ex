defmodule ExGoCDWeb.API.Admin.EncryptionController do
  @moduledoc """
  POST /api/admin/encrypt — Encrypts a plain text value using the server's AES cipher.

  GoCD parity: EncryptionControllerDelegate.encrypt() in api-encryption-v1.
  Accepts `{"value": "plaintext"}` and returns `{"encrypted_value": "AES:iv:ciphertext"}`.

  Only admin users can call this endpoint (enforced via :api pipeline + TokenAuthPlug).
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Crypto

  action_fallback ExGoCDWeb.FallbackController

  @doc """
  POST /api/admin/encrypt

  Request body:
    {"value": "secret-text-to-encrypt"}

  Response (200):
    {"encrypted_value": "AES:<base64_iv>:<base64_ciphertext>"}

  Errors:
    400 — missing "value" key
    500 — encryption failed (unexpected)
  """
  def encrypt(conn, params) do
    case Map.get(params, "value") do
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing parameter 'value'"})

      "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Parameter 'value' must not be empty"})

      value when is_binary(value) ->
        encrypted = Crypto.encrypt(value)
        json(conn, %{encrypted_value: encrypted})
    end
  end
end
