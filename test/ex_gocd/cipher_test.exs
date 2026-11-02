defmodule ExGoCD.CipherTest do
  @moduledoc """
  Secure environment variables are stored encrypted. What matters is that what
  goes in comes back out, that two equal values do not look equal in the
  database, and that a value that has been tampered with is refused rather than
  silently turned into something else.
  """
  use ExUnit.Case, async: false

  alias ExGoCD.Cipher

  @key_env "CIPHER_KEY"

  setup do
    previous = System.get_env(@key_env)
    on_exit(fn -> restore(@key_env, previous) end)
    :ok
  end

  describe "encrypt/1 and decrypt/1" do
    test "a value comes back as it went in" do
      plaintexts = [
        "",
        "hunter2",
        String.duplicate("a", 15),
        String.duplicate("a", 16),
        String.duplicate("a", 17),
        "correct horse battery staple ✓"
      ]

      for plaintext <- plaintexts do
        assert plaintext |> Cipher.encrypt() |> Cipher.decrypt() == plaintext
      end
    end

    test "the same value encrypts differently every time" do
      first = Cipher.encrypt("hunter2")
      second = Cipher.encrypt("hunter2")

      refute first == second
      assert Cipher.decrypt(first) == Cipher.decrypt(second)
    end

    test "the ciphertext is base64, so it can be stored as a string" do
      assert Cipher.encrypt("hunter2") =~ ~r/\A[A-Za-z0-9+\/=]+\z/
    end
  end

  describe "safe_decrypt/1" do
    test "answers with the value it could read" do
      assert Cipher.safe_decrypt(Cipher.encrypt("hunter2")) == {:ok, "hunter2"}
    end

    test "answers :error for a value that is not a ciphertext" do
      assert Cipher.safe_decrypt("not a ciphertext") == :error
      assert Cipher.safe_decrypt("") == :error
    end

    test "answers :error for a ciphertext that was cut short" do
      ciphertext = Cipher.encrypt("hunter2")

      assert Cipher.safe_decrypt(binary_part(ciphertext, 0, 12)) == :error
    end
  end

  describe "when CIPHER_KEY names the key" do
    test "a value encrypts and decrypts under the configured key" do
      set(@key_env, Base.encode64(:binary.copy(<<7>>, 32)))

      assert "hunter2" |> Cipher.encrypt() |> Cipher.decrypt() == "hunter2"
    end

    test "a value written under one key cannot be read under another" do
      set(@key_env, Base.encode64(:binary.copy(<<7>>, 32)))
      ciphertext = Cipher.encrypt("hunter2")

      set(@key_env, Base.encode64(:binary.copy(<<9>>, 32)))

      assert Cipher.safe_decrypt(ciphertext) == :error
    end

    test "a key that is not base64 is used as material for a key" do
      set(@key_env, "a pass phrase, of any length at all")

      assert "hunter2" |> Cipher.encrypt() |> Cipher.decrypt() == "hunter2"
    end
  end

  defp set(name, value), do: System.put_env(name, value)

  defp restore(name, nil), do: System.delete_env(name)
  defp restore(name, value), do: System.put_env(name, value)
end
