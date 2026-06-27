defmodule ExGoCD.Crypto do
  @moduledoc """
  GoCD-compatible encryption for secrets, passwords, and secure variables.

  Mirrors GoCD's GoCipher + AESEncrypter + AESCipherProvider architecture:

  ## Crypto Agility (GoCD parity)
  - **Primary**: AES-128/CBC/PKCS5Padding with random IV per encryption
  - **Format**: `AES:<base64_iv>:<base64_ciphertext>`
  - **Key storage**: hex-encoded in `config/cipher.aes` (auto-generated on first use)
  - **Thread-safe**: cached key with ETS-based singleton pattern
  - **No DES**: we skip GoCD's legacy DES migration path — AES-only from day one

  ## Usage
      ExGoCD.Crypto.encrypt("my-password")  # => "AES:abc123...:def456..."
      ExGoCD.Crypto.decrypt(cipher_text)    # => "my-password"
  """

  @cipher_file "cipher.aes"
  @key_bytes 16

  # ── Public API ────────────────────────────────────────────────────────────

  @doc "Encrypts plain text. Returns AES:<iv>:<cipher> string."
  @spec encrypt(String.t()) :: String.t()
  def encrypt(plain_text) when is_binary(plain_text) do
    key = get_key()
    iv = :crypto.strong_rand_bytes(16)
    cipher_text = :crypto.crypto_one_time(:aes_128_cbc, key, iv, pad(plain_text), true)
    "AES:" <> Base.encode64(iv) <> ":" <> Base.encode64(cipher_text)
  end

  @doc "Decrypts an AES:<iv>:<cipher> string. Returns plain text."
  @spec decrypt(String.t()) :: {:ok, String.t()} | :error
  def decrypt("AES:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [iv_b64, cipher_b64] ->
        key = get_key()

        with {:ok, iv} <- safe_decode64(iv_b64),
             {:ok, cipher_text} <- safe_decode64(cipher_b64) do
          try do
            plain = :crypto.crypto_one_time(:aes_128_cbc, key, iv, cipher_text, false)
            {:ok, unpad(plain)}
          rescue
            _ -> :error
          end
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def decrypt(_), do: :error

  @doc "Returns true if the cipher text looks like AES-encrypted."
  @spec is_aes?(String.t()) :: boolean()
  def is_aes?("AES:" <> _), do: true
  def is_aes?(_), do: false

  @doc "Securely compares two encrypted passwords (decrypts both before comparing)."
  @spec password_equals?(String.t(), String.t()) :: boolean()
  def password_equals?(p1, p2) when p1 == p2, do: true

  def password_equals?(p1, p2) do
    with {:ok, d1} <- decrypt(p1),
         {:ok, d2} <- decrypt(p2) do
      d1 == d2
    else
      _ -> false
    end
  end

  # ── Key management (GoCD AESCipherProvider parity) ────────────────────────

  defp get_key do
    case :persistent_term.get({__MODULE__, :key}, nil) do
      nil ->
        key = load_or_generate_key()
        :persistent_term.put({__MODULE__, :key}, key)
        key

      key ->
        key
    end
  end

  defp load_or_generate_key do
    path = cipher_path()

    if File.exists?(path) do
      path
      |> File.read!()
      |> String.trim()
      |> Base.decode16!(case: :lower)
    else
      key = :crypto.strong_rand_bytes(@key_bytes)
      path |> Path.dirname() |> File.mkdir_p!()
      File.write!(path, Base.encode16(key, case: :lower))
      key
    end
  end

  defp cipher_path do
    config_dir = Application.get_env(:ex_gocd, :config_dir) || Path.join("config", "")
    Path.join(config_dir, @cipher_file)
  end

  # ── PKCS5 padding (GoCD compatibility) ────────────────────────────────────

  defp pad(data) do
    block_size = 16
    pad_len = block_size - rem(byte_size(data), block_size)
    data <> String.duplicate(<<pad_len>>, pad_len)
  end

  defp unpad(data) do
    pad_len = :binary.last(data)
    binary_part(data, 0, byte_size(data) - pad_len)
  end

  defp safe_decode64(str) do
    case Base.decode64(str) do
      {:ok, data} -> {:ok, data}
      :error -> :error
    end
  end

  # ── Test helpers ──────────────────────────────────────────────────────────

  @doc "Resets the cached key (for tests)."
  def reset_key do
    :persistent_term.erase({__MODULE__, :key})
  end
end
