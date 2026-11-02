defmodule ExGoCDWeb.ApiSpecTest do
  @moduledoc """
  The OpenAPI document is what a client generator reads and what the Swagger UI
  beside it renders. It is built from the router at request time, so a document
  that cannot be built takes every API call with it — `PutApiSpec` runs on each
  one.
  """
  use ExGoCDWeb.ConnCase, async: true

  describe "GET /api/openapi" do
    test "answers an OpenAPI 3 document", %{conn: conn} do
      body = conn |> get("/api/openapi") |> json_response(200)

      assert body["openapi"] =~ "3."
      assert body["info"]["title"] =~ "GoCD"
      assert body["info"]["version"]
    end

    test "lists the API routes, each of which the router serves", %{conn: conn} do
      body = conn |> get("/api/openapi") |> json_response(200)

      assert map_size(body["paths"]) > 0

      for {path, operations} <- body["paths"], {method, _operation} <- operations do
        assert routed?(method, path),
               "#{String.upcase(method)} #{path} is in the spec but not in the router"
      end
    end

    test "groups operations under tags it also declares", %{conn: conn} do
      body = conn |> get("/api/openapi") |> json_response(200)

      declared = MapSet.new(body["tags"], & &1["name"])

      used =
        for {_path, operations} <- body["paths"],
            {_method, operation} <- operations,
            tag <- operation["tags"],
            do: tag

      assert MapSet.subset?(MapSet.new(used), declared)
    end
  end

  describe "GET /swaggerui" do
    test "serves the page that reads the document", %{conn: conn} do
      conn = get(conn, "/swaggerui")

      assert conn.status == 200
      assert conn.resp_body =~ "swagger"
    end
  end

  # A path in the spec is a template; the router wants values where the braces
  # are, so anything will do to ask whether the route exists.
  defp routed?(method, path) do
    concrete = Regex.replace(~r/\{[^}]+\}/, path, "x")

    Phoenix.Router.route_info(ExGoCDWeb.Router, String.upcase(method), concrete, "localhost") !=
      :error
  end
end
