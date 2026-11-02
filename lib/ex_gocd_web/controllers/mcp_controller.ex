defmodule ExGoCDWeb.McpController do
  @moduledoc """
  The MCP endpoint: JSON-RPC over the Streamable HTTP transport.

  `POST /mcp` carries one JSON-RPC message and is answered with one JSON object.
  The transport also allows an SSE stream and a session header; this server
  offers neither, so `GET` and `DELETE` answer 405 and every request is
  self-contained — which is what makes it safe to talk to over a single port
  from a client that has no idea what order things will be called in.

  `Origin`, when present, must name this host. That is the DNS-rebinding defence
  the specification asks for, and it costs nothing for a normal MCP client,
  which sends no `Origin` at all. `MCP-Protocol-Version`, when present, must be
  a revision this server speaks: a client that skipped the headers of a newer
  revision is asked to initialize again rather than answered in a language it
  does not know.

  Who the caller is — and what to say when there is nobody — belongs to
  `ExGoCDWeb.Plugs.McpAuth`, which runs before this controller.
  """

  use ExGoCDWeb, :controller

  alias ExGoCD.Mcp
  alias ExGoCDWeb.Mcp.{BaseUrl, Protocol}

  @allowed "POST"

  def handle(conn, _params) do
    with :ok <- check_origin(conn),
         :ok <- check_protocol_version(conn),
         {:ok, message} <- message(conn) do
      respond(conn, Protocol.handle(message, ctx(conn)))
    else
      {:error, :origin} ->
        refuse(conn, 403, "Origin is not this host.")

      {:error, :protocol_version} ->
        refuse(conn, 400, "Unsupported MCP-Protocol-Version.")

      {:error, :message} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          Jason.encode!(%{
            "jsonrpc" => "2.0",
            "id" => nil,
            "error" => %{"code" => -32_600, "message" => "Expected one JSON-RPC 2.0 message."}
          })
        )
    end
  end

  @doc "No server-initiated stream: the transport lets a server decline with 405."
  def stream(conn, _params), do: not_allowed(conn)

  @doc "No sessions to terminate: the endpoint is stateless."
  def terminate(conn, _params), do: not_allowed(conn)

  defp ctx(conn) do
    %{
      user: conn.assigns.mcp_user,
      base_url: BaseUrl.url(conn),
      remote_ip: remote_ip(conn)
    }
  end

  defp respond(conn, {:reply, payload}) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(payload))
  end

  defp respond(conn, :accepted), do: send_resp(conn, 202, "")

  defp respond(conn, {:invalid_request, payload}) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, Jason.encode!(payload))
  end

  defp not_allowed(conn) do
    conn
    |> put_resp_header("allow", @allowed)
    |> send_resp(405, "")
  end

  defp refuse(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{"error" => "invalid_request", "message" => message}))
  end

  defp check_origin(conn) do
    case get_req_header(conn, "origin") do
      [] -> :ok
      [origin | _rest] -> if same_host?(origin, conn.host), do: :ok, else: {:error, :origin}
    end
  end

  defp same_host?(origin, host) do
    case URI.parse(origin) do
      %URI{host: nil} -> false
      %URI{host: origin_host} -> String.downcase(origin_host) == String.downcase(host)
    end
  end

  defp check_protocol_version(conn) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] ->
        :ok

      [version | _rest] ->
        if Mcp.protocol_version?(version), do: :ok, else: {:error, :protocol_version}
    end
  end

  # The endpoint's parser hands over a map for a JSON object and a list for a
  # batch; MCP has no batches, and an empty body is not a message either.
  defp message(%{body_params: params}) when is_map(params) and map_size(params) > 0,
    do: {:ok, params}

  defp message(_conn), do: {:error, :message}

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
