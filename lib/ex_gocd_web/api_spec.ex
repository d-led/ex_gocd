defmodule ExGoCDWeb.ApiSpec do
  @moduledoc """
  OpenAPI 3 specification for the ex_gocd server.

  Auto-generates paths from the Phoenix router routes.
  Uses route metadata (controller, action) to produce basic operation entries.
  Only API controllers are included; UI/auth routes are excluded.
  Served at /api/openapi (JSON) and /swaggerui (Swagger UI).
  """
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Info, OpenApi, Operation, PathItem, Response, Server, Tag}
  alias ExGoCDWeb.{Endpoint, Router}

  @valid_methods MapSet.new(~w(get put post delete options head patch trace)a)

  # ── controllers whose routes appear in the spec ──────────────────────

  @api_controllers %{
    # namespace ExGoCDWeb.API
    ExGoCDWeb.API.AgentController => "Agents",
    ExGoCDWeb.API.PipelineOperationsController => "Pipeline Operations",
    ExGoCDWeb.API.PipelineInstanceController => "Pipeline Instances",
    ExGoCDWeb.API.StageController => "Stages",
    ExGoCDWeb.API.JobController => "Jobs",
    ExGoCDWeb.API.BuildConsoleController => "Builds",
    ExGoCDWeb.API.UserController => "Users",
    ExGoCDWeb.API.WebhookController => "Webhooks",
    ExGoCDWeb.API.DashboardController => "Dashboard",
    ExGoCDWeb.API.VersionController => "Version",
    ExGoCDWeb.API.StatsController => "Stats",
    ExGoCDWeb.API.AnalyticsController => "Analytics",
    ExGoCDWeb.API.ConfigRepoController => "Config Repos",
    ExGoCDWeb.API.PersonalAccessTokenController => "Access Tokens",
    ExGoCDWeb.API.TestController => "Test Helpers",
    # namespace ExGoCDWeb.API.Admin
    ExGoCDWeb.API.Admin.PipelineConfigController => "Pipeline Config",
    ExGoCDWeb.API.Admin.TemplateController => "Templates",
    ExGoCDWeb.API.Admin.EnvironmentController => "Environments",
    ExGoCDWeb.API.Admin.MaintenanceModeController => "Maintenance Mode",
    ExGoCDWeb.API.Admin.BackupController => "Backup",
    # non-API-namespaced controllers that serve data (not UI)
    ExGoCDWeb.AdminAgentController => "Agents",
    ExGoCDWeb.AgentRemotingController => "Agent Remoting",
    ExGoCDWeb.ArtifactsController => "Artifacts",
    ExGoCDWeb.ValueStreamMapController => "Value Stream Map",
    ExGoCDWeb.CCTrayController => "CCTray"
  }

  # ── tags derived from controller map (sorted by name) ───────────────

  @tags @api_controllers
        |> Map.values()
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map(&%Tag{name: &1})

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
      tags: @tags
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
    |> Enum.filter(&api_route?/1)
    |> Enum.group_by(&route_path/1)
    |> Enum.map(fn {path, routes} ->
      ops =
        routes
        |> Enum.map(&build_operation/1)
        |> Enum.reduce(%{}, fn {method, op}, acc -> Map.put(acc, method, op) end)

      {path, struct!(PathItem, ops)}
    end)
    |> Enum.into(%{})
  end

  defp api_route?(route) do
    MapSet.member?(@valid_methods, route.verb) and
      Map.has_key?(@api_controllers, route.plug)
  end

  defp route_path(route), do: route.path

  defp build_operation(route) do
    method = route.verb
    tag = Map.fetch!(@api_controllers, route.plug)
    summary = summary(method, tag, route)

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

  defp summary(method, tag, route) do
    action =
      case Map.get(route, :plug_opts) || Map.get(route, :opts) do
        action when is_atom(action) -> " · #{action}"
        _ -> ""
      end

    "#{method |> to_string() |> String.upcase()} #{tag}#{action}"
  end

  defp operation_id(route) do
    opts =
      case Map.get(route, :plug_opts) || Map.get(route, :opts) do
        opts when is_atom(opts) -> ".#{opts}"
        _opts -> ""
      end

    "#{route.plug}#{opts}"
  end
end
