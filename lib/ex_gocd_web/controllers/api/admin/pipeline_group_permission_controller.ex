defmodule ExGoCDWeb.API.Admin.PipelineGroupPermissionController do
  use ExGoCDWeb, :controller
  alias ExGoCD.Accounts

  @doc "GET /api/admin/pipeline_group_permissions?user_id=..."
  def index(conn, %{"user_id" => user_id}) do
    perms = Accounts.list_pipeline_group_permissions(String.to_integer(user_id))
    json(conn, %{data: perms})
  end

  def index(conn, _params) do
    json(conn, %{error: "user_id query parameter is required"})
  end

  @doc "POST /api/admin/pipeline_group_permissions"
  def create(conn, %{"user_id" => user_id, "pipeline_group" => group, "role" => role}) do
    case Accounts.grant_pipeline_group_permission(String.to_integer(user_id), group, role) do
      {:ok, perm} ->
        conn |> put_status(:created) |> json(%{data: perm})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(changeset)})
    end
  end

  @doc "DELETE /api/admin/pipeline_group_permissions?user_id=...&pipeline_group=..."
  def delete(conn, %{"user_id" => user_id, "pipeline_group" => group}) do
    case Accounts.revoke_pipeline_group_permission(String.to_integer(user_id), group) do
      {:ok, _} ->
        conn |> json(%{message: "Permission revoked"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Permission not found"})
    end
  end

  defp changeset_errors(cs),
    do:
      Ecto.Changeset.traverse_errors(cs, fn {m, o} ->
        Enum.reduce(o, m, fn {k, v}, a -> String.replace(a, "%{#{k}}", to_string(v)) end)
      end)
end
