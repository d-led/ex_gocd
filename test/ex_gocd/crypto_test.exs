defmodule ExGoCD.CryptoTest do
  use ExUnit.Case, async: true

  alias ExGoCD.Crypto

  setup do
    # Reset key between tests to simulate fresh state
    on_exit(fn -> Crypto.reset_key() end)
    :ok
  end

  describe "encrypt/decrypt (GoCD AESEncrypter parity)" do
    test "encrypts and decrypts plain text" do
      cipher = Crypto.encrypt("p@ssw0rd")
      assert String.starts_with?(cipher, "AES:")
      assert {:ok, "p@ssw0rd"} = Crypto.decrypt(cipher)
    end

    test "encryption produces different ciphertext each time (random IV)" do
      c1 = Crypto.encrypt("same-password")
      c2 = Crypto.encrypt("same-password")
      assert c1 != c2
      # Both decrypt to the same plain text
      assert {:ok, "same-password"} = Crypto.decrypt(c1)
      assert {:ok, "same-password"} = Crypto.decrypt(c2)
    end

    test "preserves leading and trailing spaces" do
      cipher = Crypto.encrypt("  spaced  ")
      assert {:ok, "  spaced  "} = Crypto.decrypt(cipher)
    end

    test "handles empty string" do
      cipher = Crypto.encrypt("")
      assert {:ok, ""} = Crypto.decrypt(cipher)
    end

    test "handles unicode text" do
      cipher = Crypto.encrypt("café-密码-パスワード")
      assert {:ok, "café-密码-パスワード"} = Crypto.decrypt(cipher)
    end
  end

  describe "aes?/1 (GoCD canDecrypt parity)" do
    test "returns true for AES-prefixed cipher text" do
      cipher = Crypto.encrypt("secret")
      assert Crypto.aes?(cipher)
    end

    test "returns false for non-AES text" do
      refute Crypto.aes?("plain-text")
      refute Crypto.aes?("DES:old-format")
      refute Crypto.aes?("")
    end
  end

  describe "decrypt/1 error handling (GoCD tampering parity)" do
    test "returns :error for non-AES cipher text" do
      assert Crypto.decrypt("not-encrypted") == :error
    end

    test "returns :error for tampered cipher text" do
      cipher = Crypto.encrypt("secret")
      # Tamper with the ciphertext portion
      [prefix, iv, ct] = String.split(cipher, ":")
      tampered = "#{prefix}:#{iv}:Zm9vYmFy" <> Base.encode64("tamper")
      assert Crypto.decrypt(tampered) == :error
    end

    test "returns :error for wrong format" do
      assert Crypto.decrypt("AES:only-two-parts") == :error
      assert Crypto.decrypt("AES:a:b:c:d") == :error
    end

    test "returns :error for invalid base64" do
      assert Crypto.decrypt("AES:!!!:!!!") == :error
    end
  end

  describe "password_equals?/2 (GoCD passwordEquals parity)" do
    test "same password encrypts differently but compares equal" do
      c1 = Crypto.encrypt("admin123")
      c2 = Crypto.encrypt("admin123")
      assert c1 != c2
      assert Crypto.password_equals?(c1, c2)
    end

    test "different passwords compare unequal" do
      c1 = Crypto.encrypt("admin123")
      c2 = Crypto.encrypt("wrong")
      refute Crypto.password_equals?(c1, c2)
    end

    test "nil-safe comparison" do
      refute Crypto.password_equals?(Crypto.encrypt("x"), "garbage")
      refute Crypto.password_equals?("garbage", Crypto.encrypt("x"))
    end
  end

  describe "key persistence (GoCD AESCipherProvider parity)" do
    test "same key used across encrypt/decrypt cycles" do
      cipher = Crypto.encrypt("persistent-test")
      # Reset the module's state but the key file persists
      Crypto.reset_key()
      assert {:ok, "persistent-test"} = Crypto.decrypt(cipher)
    end

    test "key is stable across multiple encryptions" do
      c1 = Crypto.encrypt("first")
      c2 = Crypto.encrypt("second")
      assert {:ok, "first"} = Crypto.decrypt(c1)
      assert {:ok, "second"} = Crypto.decrypt(c2)
    end
  end
end
