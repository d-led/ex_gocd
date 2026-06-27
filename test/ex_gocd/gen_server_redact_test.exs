defmodule ExGoCD.GenServerRedactTest do
  use ExUnit.Case, async: true

  alias ExGoCD.GenServerRedact

  describe "redact/1" do
    test "redacts known-sensitive string keys" do
      map = %{"password" => "s3cret", "token" => "abc123", "host" => "example.com"}
      result = GenServerRedact.redact(map)

      assert result["password"] == "***REDACTED***"
      assert result["token"] == "***REDACTED***"
      assert result["host"] == "example.com"
    end

    test "redacts known-sensitive atom keys" do
      map = %{password: "s3cret", api_key: "key-123", name: "test"}
      result = GenServerRedact.redact(map)

      assert result[:password] == "***REDACTED***"
      assert result[:api_key] == "***REDACTED***"
      assert result[:name] == "test"
    end

    test "redacts nested maps" do
      map = %{
        "config" => %{
          "auth" => %{"bearer" => "tok-123", "username" => "admin"},
          "url" => "https://example.com"
        }
      }

      result = GenServerRedact.redact(map)
      assert get_in(result, ["config", "auth", "bearer"]) == "***REDACTED***"
      assert get_in(result, ["config", "auth", "username"]) == "admin"
      assert get_in(result, ["config", "url"]) == "https://example.com"
    end

    test "redacts keys matching _key suffix" do
      map = %{"access_key" => "AKIA...", "secret_key" => "wJalr...", "region" => "us-east-1"}
      result = GenServerRedact.redact(map)

      assert result["access_key"] == "***REDACTED***"
      assert result["secret_key"] == "***REDACTED***"
      assert result["region"] == "us-east-1"
    end

    test "does not exceed max depth" do
      deep = %{"a" => %{"b" => %{"c" => %{"d" => %{"password" => "deep"}}}}}
      result = GenServerRedact.redact(deep)

      # At depth 3, "d" is a map but we're at max depth — returned as-is
      assert get_in(result, ["a", "b", "c", "d", "password"]) == "deep"
    end

    test "passes through primitives unchanged" do
      assert GenServerRedact.redact("hello") == "hello"
    end

    test "handles empty map" do
      assert GenServerRedact.redact(%{}) == %{}
    end

    test "handles list of maps" do
      list = [%{"password" => "a"}, %{"password" => "b"}]
      result = GenServerRedact.redact(list)

      assert length(result) == 2
      assert Enum.at(result, 0)["password"] == "***REDACTED***"
      assert Enum.at(result, 1)["password"] == "***REDACTED***"
    end
  end

  describe "redact_pdict/1" do
    test "redacts sensitive keys in process dictionary" do
      pdict = [token: "abc", user: "admin", some_ref: make_ref()]
      result = GenServerRedact.redact_pdict(pdict)

      assert result[:token] == "***REDACTED***"
      assert result[:user] == "admin"
    end

    test "passes through non-keyword entries" do
      pdict = ["not_a_tuple", {:ok, "value"}]
      result = GenServerRedact.redact_pdict(pdict)

      assert Enum.at(result, 0) == "not_a_tuple"
      assert Enum.at(result, 1) == {:ok, "value"}
    end
  end

  describe "format_status integration" do
    @tag :skip
    test "GenServer with use ExGoCD.GenServerRedact redacts state on crash" do
      # Define inline to guarantee compile order
      defmodule IntegrationServer do
        use GenServer
        use ExGoCD.GenServerRedact

        @impl true
        def init(state), do: {:ok, state}
      end

      {:ok, pid} = GenServer.start_link(IntegrationServer, %{password: "s3cret", name: "test"})

      # sys:get_status returns {:status, pid, module, [pdict, run, parent, logs, items]}
      # The formatted state from format_status/2 is the last element of the items list.
      status = :sys.get_status(pid)
      formatted_state = status |> elem(3) |> List.last()

      assert formatted_state[:password] == "***REDACTED***"
      assert formatted_state[:name] == "test"

      GenServer.stop(pid)
    end
  end
end
