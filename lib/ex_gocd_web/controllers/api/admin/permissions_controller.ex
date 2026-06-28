defmodule ExGoCDWeb.API.Admin.PermissionsController do
  use ExGoCDWeb, :controller

  alias ExGoCD.{Accounts, Repo}

  @system_roles %{
    "admin" => %{
      description: "Full system access",
      permissions: ~w(admin_read admin_write pipeline_operate)
    },
    "operator" => %{
      description: "Can operate pipelines",
      permissions: ~w(pipeline_operate pipeline_read)
    },
    "viewer" => %{description: "Read-only access", permissions: ~w(pipeline_read)}
  }

  @doc "GET /api/admin/permissions — lists system roles and all granted permissions"
  def index(conn, _params) do
    roles =
      Enum.map(@system_roles, fn {name, info} ->
        %{role: name, description: info.description, permissions: info.permissions}
      end)

    pipeline_group_permissions =
      Accounts.PipelineGroupPermission
      |> Repo.all()
      |> Repo.preload(:user)
      |> Enum.map(fn p ->
        %{
          user_id: p.user_id,
          username: p.user && p.user.username,
          pipeline_group: p.pipeline_group,
          role: p.role
        }
      end)

    json(conn, %{
      roles: roles,
      pipeline_group_permissions: pipeline_group_permissions
    })
  end
end
