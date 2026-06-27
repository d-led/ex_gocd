defmodule ExGoCDWeb.API.Admin.PermissionsController do
  use ExGoCDWeb, :controller

  @system_roles %{
    "admin" => %{description: "Full system access", permissions: ~w(admin_read admin_write pipeline_operate)},
    "operator" => %{description: "Can operate pipelines", permissions: ~w(pipeline_operate pipeline_read)},
    "viewer" => %{description: "Read-only access", permissions: ~w(pipeline_read)}
  }

  @doc "GET /api/admin/permissions — lists available system roles"
  def index(conn, _params) do
    roles = Enum.map(@system_roles, fn {name, info} ->
      %{role: name, description: info.description, permissions: info.permissions}
    end)
    json(conn, %{roles: roles})
  end
end
