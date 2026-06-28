defmodule ExGoCDWeb.API.Admin.RoleController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.Role

  def index(conn, _params) do
    roles = Accounts.list_roles() |> Enum.map(&role_json/1)
    json(conn, %{_embedded: %{roles: roles}})
  end

  def show(conn, %{"role_name" => name}) do
    case Accounts.get_role_by_name(name) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "Role not found"})
      role -> json(conn, role_json(role))
    end
  end

  def create(conn, %{"role" => params}) do
    case Accounts.create_role(params) do
      {:ok, role} ->
        conn |> put_status(:created) |> json(role_json(role))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: errors_json(changeset)})
    end
  end

  def update(conn, %{"role_name" => name, "role" => params}) do
    case Accounts.get_role_by_name(name) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Role not found"})

      role ->
        case Accounts.update_role(role, params) do
          {:ok, updated} ->
            json(conn, role_json(updated))

          {:error, changeset} ->
            conn |> put_status(:unprocessable_entity) |> json(%{errors: errors_json(changeset)})
        end
    end
  end

  def delete(conn, %{"role_name" => name}) do
    case Accounts.get_role_by_name(name) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Role not found"})

      role ->
        case Accounts.delete_role(role) do
          {:ok, _} ->
            send_resp(conn, :no_content, "")

          {:error, :in_use} ->
            conn
            |> put_status(:conflict)
            |> json(%{error: "Role is in use by pipeline group permissions"})
        end
    end
  end

  defp role_json(%Role{} = role) do
    %{
      name: role.name,
      type: role.type,
      users: role.users || [],
      auth_config_id: role.auth_config_id,
      properties: role.properties || %{},
      policy: role.policy || %{}
    }
  end

  defp errors_json(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
