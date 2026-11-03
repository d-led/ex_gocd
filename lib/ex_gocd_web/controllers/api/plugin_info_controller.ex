defmodule ExGoCDWeb.API.PluginInfoController do
  @moduledoc """
  GoCD Plugin Info API (api-plugin-infos-v7).
  Returns metadata about the server and its built-in capabilities.
  ex_gocd has no external plugins — capabilities are built-in.
  """
  use ExGoCDWeb, :controller

  @doc "GET /api/plugin_info"
  def index(conn, _params) do
    plugins = builtin_plugins()

    conn
    |> put_status(:ok)
    |> json(%{
      _links: %{
        self: %{href: "/api/plugin_info"},
        doc: %{href: "https://github.com/d-led/ex_gocd"}
      },
      plugins: plugins
    })
  end

  @doc "GET /api/plugin_info/:plugin_id"
  def show(conn, %{"plugin_id" => plugin_id}) do
    case Enum.find(builtin_plugins(), &(&1.id == plugin_id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Plugin not found: #{plugin_id}"})

      plugin ->
        conn
        |> put_status(:ok)
        |> json(present(plugin))
    end
  end

  # The per-plugin shape from api.go.cd: identity, health, where it came from and
  # which extension points it fills. A built-in has no file on disk, hence the
  # null location and bundled_plugin.
  defp present(plugin) do
    %{
      _links: %{
        self: %{href: "/api/plugin_info/#{plugin.id}"},
        doc: %{href: "https://github.com/d-led/ex_gocd"},
        find: %{href: "/api/plugin_info/:plugin_id"}
      },
      id: plugin.id,
      status: plugin.status,
      plugin_file_location: nil,
      bundled_plugin: true,
      about: plugin.about,
      extensions: [%{type: plugin.type}]
    }
  end

  defp builtin_plugins do
    [
      %{
        id: "ex_gocd.config_repo.gocd_yaml",
        version: "0.1.0",
        type: "configrepo",
        status: %{state: "active"},
        about: %{
          name: "GoCD YAML Config Repo",
          version: "0.1.0",
          target_go_version: "25.1.0",
          description: "Built-in YAML pipeline-as-code config repository support",
          vendor: %{name: "ex_gocd"},
          target_operating_systems: []
        }
      },
      %{
        id: "ex_gocd.scm.git",
        version: "0.1.0",
        type: "scm",
        status: %{state: "active"},
        about: %{
          name: "Git Material",
          version: "0.1.0",
          target_go_version: "25.1.0",
          description: "Built-in Git SCM material support",
          vendor: %{name: "ex_gocd"},
          target_operating_systems: []
        }
      },
      %{
        id: "ex_gocd.notification.stdout",
        version: "0.1.0",
        type: "notification",
        status: %{state: "active"},
        about: %{
          name: "Stdout Notification",
          version: "0.1.0",
          target_go_version: "25.1.0",
          description: "Built-in notification via server logs",
          vendor: %{name: "ex_gocd"},
          target_operating_systems: []
        }
      }
    ]
  end
end
