defmodule ExGoCDWeb.ApiSpec do
  @moduledoc """
  OpenAPI 3 specification for the ex_gocd server — auto-generated from router and controllers.

  Uses open_api_spex to extract paths, schemas, and operations from the Phoenix router.
  Served at /api/openapi (JSON) and /swaggerui (Swagger UI).
  """
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Info, OpenApi, Paths, Server}
  alias ExGoCDWeb.{Endpoint, Router}

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        Server.from_endpoint(Endpoint)
      ],
      info: %Info{
        title: "ex_gocd — GoCD-compatible CI/CD Server",
        version: version(),
        description: """
        A GoCD-compatible CI/CD server built with Elixir and Phoenix.

        Automatically generated API specification. All endpoints are derived from
        the Phoenix router and controller specs.
        """
      },
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp version do
    case :application.get_key(:ex_gocd, :vsn) do
      {:ok, vsn} -> List.to_string(vsn)
      :undefined -> "0.0.0"
    end
  end
end
