defmodule EnterpriseHierarchy.API do
  @moduledoc """
  HTTP API for the Enterprise Hierarchy plugin.
  Runs on port 4110 (configurable via HIERARCHY_API_PORT env var).

  ## Endpoints

    GET  /api/hierarchy — returns current org tree as JSON
    PUT  /api/hierarchy — updates org tree from JSON body
    GET  /health          — health check
  """
  use Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  get "/health" do
    send_resp(conn, 200, "OK")
  end

  get "/api/hierarchy" do
    tree = EnterpriseHierarchy.org_tree()
    conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(tree, pretty: true))
  end

  put "/api/hierarchy" do
    case conn.body_params do
      %{"id" => _, "name" => _} = body ->
        EnterpriseHierarchy.update_tree(body)
        conn |> send_resp(200, Jason.encode!(%{message: "Hierarchy updated", nodes: count_nodes(body)}))

      _ ->
        conn |> send_resp(400, Jason.encode!(%{error: "Invalid hierarchy JSON. Expected {\"id\":..., \"name\":..., \"children\":[...]}"}))
    end
  end

  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "Not found"}))
  end

  defp count_nodes(node) do
    1 + Enum.reduce(node["children"] || node[:children] || [], 0, fn c, acc -> acc + count_nodes(c) end)
  end
end
