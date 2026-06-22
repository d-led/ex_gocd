defmodule ExGoCDWeb.ApiSpec do
  @moduledoc """
  OpenAPI 3 specification for the ex_gocd server.

  Auto-generates paths from the Phoenix router routes.
  Uses route metadata (controller, action) to produce basic operation entries.
  Served at /api/openapi (JSON) and /swaggerui (Swagger UI).
  """
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Info, OpenApi, Operation, PathItem, Response, Server, Tag}
  alias ExGoCDWeb.{Endpoint, Router}

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [Server.from_endpoint(Endpoint)],
      info: %Info{
        title: "ex_gocd — GoCD-compatible CI/CD Server API",
        version: version(),
        description: """
        Auto-generated API reference for the ex_gocd CI/CD server.

        All endpoints mirror GoCD's JSON API. Use the /go/ prefix for
        GoCD-compatible paths (e.g., /go/api/agents vs /api/agents).
        """
      },
      paths: build_paths(),
      tags: [
        %Tag{name: "Agents", description: "Agent registration and management"},
        %Tag{name: "Pipelines", description: "Pipeline triggers, pause, unlock, schedule"},
        %Tag{name: "Materials", description: "Material polling and notifications"},
        %Tag{name: "Stages", description: "Stage instances and operations"},
        %Tag{name: "Jobs", description: "Job history and console logs"},
        %Tag{name: "Version", description: "Server version information"},
        %Tag{name: "Admin", description: "Administrative operations"},
        %Tag{name: "Config Repos", description: "Config repository management"},
        %Tag{name: "Users", description: "User and permission management"},
        %Tag{name: "Dashboard", description: "Pipeline dashboard"},
        %Tag{name: "CCTray", description: "CCTray XML feed"},
        %Tag{name: "Stats", description: "Server statistics"},
        %Tag{name: "Webhooks", description: "SCM webhook receivers"},
        %Tag{name: "Backup", description: "Server backup operations"},
        %Tag{name: "Artifacts", description: "Artifact download and cleanup"},
      ]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp version do
    case :application.get_key(:ex_gocd, :vsn) do
      {:ok, vsn} -> List.to_string(vsn)
      :undefined -> "0.0.0"
    end
  end

  # ── path generation ─────────────────────────────────────────────────

  defp build_paths do
    Router.__routes__()
    |> Enum.group_by(&route_path/1)
    |> Enum.map(fn {path, routes} ->
      ops = routes |> Enum.map(&build_operation/1) |> Enum.reduce(%{}, fn {method, op}, acc -> Map.put(acc, method, op) end)
      {path, struct!(PathItem, ops)}
    end)
    |> Enum.into(%{})
  end

  defp route_path(route), do: route.path

  defp build_operation(route) do
    method = route.verb |> to_string() |> String.downcase()
    tag = route_tag(route)
    summary = "#{String.upcase(method)} #{tag}"

    {method,
     %Operation{
       tags: [tag],
       summary: summary,
       operationId: operation_id(route),
       parameters: [],
       responses: %{
         "200" => %Response{description: "OK"},
         "404" => %Response{description: "Not Found"}
       }
     }}
  end

  defp operation_id(route) do
    "#{route.plug}.#{route.plug_opts}"
  end

  @tag_patterns [
    {"/agents", "Agents"},
    {"/pipelines", "Pipelines"},
    {"/materials", "Materials"},
    {"/stage", "Stages"},
    {"/job", "Jobs"},
    {"/version", "Version"},
    {"/admin", "Admin"},
    {"/config_repo", "Config Repos"},
    {"/users", "Users"},
    {"/dashboard", "Dashboard"},
    {"/cctray", "CCTray"},
    {"/stats", "Stats"},
    {"/webhooks", "Webhooks"},
    {"/backup", "Backup"},
    {"/artifacts", "Artifacts"},
  ]

  defp route_tag(route) do
    path = route_path(route)
    Enum.find_value(@tag_patterns, "General", fn {pattern, tag} ->
      if String.contains?(path, pattern), do: tag
    end)
  end
end
