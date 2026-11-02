defmodule ExGoCD.Cipher do
  @moduledoc """
  AES-256-CBC encryption for secure environment variables.
  Mirrors GoCD's GoCipher behavior.

  Uses a configurable secret key base. In production, set CIPHER_KEY
  env var to a 32-byte base64-encoded key.
  """

  @block_size 16
  @key_bytes 32

  @doc "Encrypts a plaintext value. Returns base64-encoded ciphertext."
  @spec encrypt(String.t()) :: String.t()
  def encrypt(plaintext) when is_binary(plaintext) do
    iv = :crypto.strong_rand_bytes(@block_size)
    key = cipher_key()
    ciphertext = :crypto.crypto_one_time(:aes_256_cbc, key, iv, pad(plaintext), true)
    (iv <> ciphertext) |> Base.encode64()
  end

  @doc "Decrypts a base64-encoded ciphertext. Returns plaintext or raises."
  @spec decrypt(String.t()) :: String.t()
  def decrypt(ciphertext_b64) when is_binary(ciphertext_b64) do
    <<iv::binary-@block_size, ciphertext::binary>> = Base.decode64!(ciphertext_b64)
    key = cipher_key()

    :crypto.crypto_one_time(:aes_256_cbc, key, iv, ciphertext, false)
    |> unpad()
  end

  @doc "Decrypts or returns :error instead of raising."
  def safe_decrypt(ciphertext_b64) do
    {:ok, decrypt(ciphertext_b64)}
  rescue
    _ -> :error
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  defp cipher_key do
    case System.get_env("CIPHER_KEY") do
      key when is_binary(key) and byte_size(key) >= @key_bytes ->
        case Base.decode64(key) do
          {:ok, decoded} when byte_size(decoded) >= @key_bytes ->
            binary_part(decoded, 0, @key_bytes)

          _ ->
            derive_key(key)
        end

      _ ->
        derive_key(default_key())
    end
  end

  defp default_key do
    Application.get_env(:ex_gocd, :secret_key_base) ||
      "ex_gocd_default_cipher_key_32bytes!"
  end

  defp derive_key(material) do
    :crypto.hash(:sha256, material)
  end

  defp pad(data) do
    pad_len = @block_size - rem(byte_size(data), @block_size)
    data <> String.duplicate(<<pad_len>>, pad_len)
  end

  # PKCS#7: the last byte says how many bytes of padding there are, and they all
  # carry that count. Anything else means the value was written with another key
  # or altered in storage, and a caller is better served by an error than by the
  # bytes that come out — GoCD's cipher refuses it too.
  defp unpad(data) do
    pad_len = :binary.last(data)

    if pad_len < 1 or pad_len > @block_size or
         binary_part(data, byte_size(data) - pad_len, pad_len) !=
           :binary.copy(<<pad_len>>, pad_len) do
      raise ArgumentError, "malformed padding"
    end

    binary_part(data, 0, byte_size(data) - pad_len)
  end
end
