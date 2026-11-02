defmodule ExGoCDWeb.McpControllerTest do
  @moduledoc """
  The endpoint as a client meets it: one JSON-RPC message in, one answer out,
  and a challenge instead of an answer when the caller is not who it says.
  """

  use ExGoCDWeb.ConnCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Accounts
  alias ExGoCD.Mcp.Tools

  defp rpc(conn, message) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/mcp", message)
  end

  describe "the transport" do
    test "answers an initialize with a revision and instructions", %{conn: conn} do
      body =
        conn
        |> rpc(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{"protocolVersion" => "2025-06-18"}
        })
        |> json_response(200)

      assert body["result"]["protocolVersion"] == "2025-06-18"
      assert body["result"]["instructions"] =~ "GoCD"
    end

    test "accepts a notification without answering it", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/mcp", %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

      assert response(conn, 202) == ""
    end

    test "has no stream to subscribe to and no session to end", %{conn: conn} do
      assert conn |> get("/mcp") |> response(405)
      assert build_conn() |> delete("/mcp") |> response(405)
    end

    test "refuses an Origin that is not this host", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://somewhere.else")
        |> rpc(%{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})

      assert json_response(conn, 403)["message"] == "Origin is not this host."
    end

    test "refuses a protocol revision it does not speak", %{conn: conn} do
      conn =
        conn
        |> put_req_header("mcp-protocol-version", "1999-01-01")
        |> rpc(%{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})

      assert json_response(conn, 400)["message"] =~ "Unsupported MCP-Protocol-Version"
    end
  end

  describe "tools" do
    test "lists every tool the server defines", %{conn: conn} do
      body =
        conn
        |> rpc(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
        |> json_response(200)

      assert length(body["result"]["tools"]) == Tools.count()
    end

    test "answers a read tool with text and the same facts structured", %{conn: conn} do
      body =
        conn
        |> rpc(%{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/call",
          "params" => %{"name" => "gocd_server_info", "arguments" => %{}}
        })
        |> json_response(200)

      assert [%{"type" => "text", "text" => text}] = body["result"]["content"]
      assert text =~ "pipeline(s)"
      assert body["result"]["isError"] == false
      assert Map.has_key?(body["result"]["structuredContent"], "agents")
    end

    test "reports a tool's refusal as a tool error, not a broken server", %{conn: conn} do
      body =
        conn
        |> rpc(%{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "tools/call",
          "params" => %{"name" => "gocd_describe_pipeline", "arguments" => %{}}
        })
        |> json_response(200)

      assert body["result"]["isError"] == true
      assert [%{"text" => "`name` is required."}] = body["result"]["content"]
    end
  end

  describe "the documents and the workflows" do
    test "a resource reads back the tool's own answer", %{conn: conn} do
      insert_pipeline("resource-over-http")

      body =
        conn
        |> rpc(%{
          "jsonrpc" => "2.0",
          "id" => 4,
          "method" => "resources/read",
          "params" => %{"uri" => "gocd://dashboard"}
        })
        |> json_response(200)

      assert [%{"uri" => "gocd://dashboard", "mimeType" => "application/json", "text" => text}] =
               body["result"]["contents"]

      assert Jason.decode!(text)["total"] == 1
    end

    test "a prompt is filled in over the wire", %{conn: conn} do
      body =
        conn
        |> rpc(%{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => "prompts/get",
          "params" => %{
            "name" => "diagnose_pipeline",
            "arguments" => %{"pipeline" => "build-app"}
          }
        })
        |> json_response(200)

      assert [%{"role" => "user", "content" => %{"text" => text}}] = body["result"]["messages"]
      assert text =~ "build-app"
    end
  end

  describe "identity" do
    test "a rejected token is a 401 that says where a credential comes from", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-a-token-this-server-issued")
        |> rpc(%{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})

      assert json_response(conn, 401)["error"] == "invalid_token"

      assert [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ "resource_metadata="
      assert challenge =~ "/.well-known/oauth-protected-resource"
    end

    test "with credentials required, a call that carries none gets the challenge", %{conn: conn} do
      Application.put_env(:ex_gocd, :mcp_require_auth, true)
      on_exit(fn -> Application.delete_env(:ex_gocd, :mcp_require_auth) end)

      conn = rpc(conn, %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})

      assert json_response(conn, 401)["error"] == "unauthorized"
      assert [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ "realm=\"gocd\""
      refute challenge =~ "error="
    end

    test "an access token acts as the user it was minted for", %{conn: conn} do
      pipeline = insert_pipeline("token-owned-pipeline")

      {:ok, user} =
        Accounts.create_user(%{
          username: "mcp-bot",
          display_name: "Bot",
          roles: ["admin"],
          status: "Active"
        })

      {:ok, token} = Accounts.create_user_token(user.id, "a test client")

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token.token)
        |> rpc(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{
            "name" => "gocd_set_pipeline_paused",
            "arguments" => %{"name" => pipeline.name, "paused" => true, "cause" => "by the bot"}
          }
        })
        |> json_response(200)

      assert conn["result"]["isError"] == false
      assert ExGoCD.Pipelines.get_pipeline_by_name(pipeline.name).paused_by == "mcp-bot"
    end
  end
end
