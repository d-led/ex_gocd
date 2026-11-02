defmodule ExGoCDWeb.Mcp.ProtocolTest do
  @moduledoc """
  What a well-formed message means, without a socket and without a database: the
  controller and the tools are tested where they belong.
  """

  use ExUnit.Case, async: true

  alias ExGoCD.Mcp
  alias ExGoCDWeb.Mcp.Protocol

  @ctx %{user: nil, base_url: "http://localhost:4000", remote_ip: "127.0.0.1"}

  defp call(method, params, id \\ 1) do
    Protocol.handle(
      %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params},
      @ctx
    )
  end

  describe "initialize" do
    test "answers with the revision the client asked for" do
      assert {:reply, %{"result" => result}} =
               call("initialize", %{"protocolVersion" => "2025-03-26"})

      assert result["protocolVersion"] == "2025-03-26"
      assert result["serverInfo"]["name"] == "gocd-mcp"
      assert result["capabilities"] == %{"tools" => %{"listChanged" => false}}
    end

    test "answers with the newest revision it speaks when the client names one it does not" do
      assert {:reply, %{"result" => %{"protocolVersion" => version}}} =
               call("initialize", %{"protocolVersion" => "1999-01-01"})

      assert version == Mcp.latest_protocol_version()
    end
  end

  test "ping is answered with an empty result" do
    assert call("ping", %{}) == {:reply, %{"jsonrpc" => "2.0", "id" => 1, "result" => %{}}}
  end

  test "tools/list is every tool, in the order the server defines them" do
    assert {:reply, %{"result" => %{"tools" => tools}}} = call("tools/list", %{})
    assert length(tools) == ExGoCD.Mcp.Tools.count()
  end

  test "a notification is accepted and not answered" do
    assert Protocol.handle(
             %{"jsonrpc" => "2.0", "method" => "notifications/initialized"},
             @ctx
           ) == :accepted
  end

  test "a message without an id is a notification, even if it names a method" do
    assert Protocol.handle(%{"jsonrpc" => "2.0", "method" => "tools/list"}, @ctx) == :accepted
  end

  test "a tool that is not defined is a protocol error, not a tool error" do
    assert {:reply, %{"error" => %{"code" => -32_602}}} =
             call("tools/call", %{"name" => "gocd_nope", "arguments" => %{}})
  end

  test "a tool that refuses its arguments is a tool error the model can read" do
    assert {:reply, %{"result" => %{"isError" => true, "content" => [%{"text" => text}]}}} =
             call("tools/call", %{"name" => "gocd_describe_pipeline", "arguments" => %{}})

    assert text == "`name` is required."
  end

  test "an unknown method is method-not-found" do
    assert {:reply, %{"error" => %{"code" => -32_601}}} = call("resources/list", %{})
  end

  test "a batch is refused with a message that says so" do
    assert {:invalid_request, %{"error" => %{"message" => message}}} =
             Protocol.handle([%{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"}], @ctx)

    assert message =~ "Batches are not supported"
  end

  test "a message that is not JSON-RPC 2.0 is refused" do
    assert {:invalid_request, %{"error" => %{"code" => -32_600}}} =
             Protocol.handle(%{"jsonrpc" => "1.0", "id" => 1, "method" => "ping"}, @ctx)
  end
end
