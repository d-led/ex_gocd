defmodule ExGoCDWeb.API.UserController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Accounts

  @doc "GET /api/users"
  def index(conn, _params) do
    users = Accounts.list_users()
    json(conn, %{users: Enum.map(users, &user_json/1)})
  end

  @doc "GET /api/users/:username"
  def show(conn, %{"username" => username}) do
    case Accounts.get_user_by_username(username) do
      nil ->
        conn |> put_status(:not_found) |> json(%{message: "User '#{username}' not found."})
      user ->
        json(conn, user_json(user))
    end
  end

  @doc "POST /api/users"
  def create(conn, %{"username" => username} = params) do
    case Accounts.create_user(%{
      username: username,
      display_name: params["display_name"] || username,
      roles: params["roles"] || [],
      status: params["status"] || "Active"
    }) do
      {:ok, user} ->
        conn |> put_status(:created) |> json(user_json(user))
      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{message: "Failed to create user.", errors: format_errors(changeset)})
    end
  end

  @doc "PATCH /api/users/:username"
  def update(conn, %{"username" => username} = params) do
    case Accounts.get_user_by_username(username) do
      nil ->
        conn |> put_status(:not_found) |> json(%{message: "User '#{username}' not found."})
      user ->
        attrs = Map.take(params, ~w(display_name roles status))
        attrs = if attrs == %{}, do: %{display_name: user.display_name}, else: attrs
        case Accounts.update_user(user, attrs) do
          {:ok, updated} -> json(conn, user_json(updated))
          {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{message: "Update failed.", errors: format_errors(changeset)})
        end
    end
  end

  @doc "DELETE /api/users/:username"
  def delete(conn, %{"username" => username}) do
    case Accounts.get_user_by_username(username) do
      nil ->
        conn |> put_status(:not_found) |> json(%{message: "User '#{username}' not found."})
      user ->
        Accounts.delete_user(user)
        json(conn, %{message: "User '#{username}' deleted."})
    end
  end

  defp user_json(user) do
    %{
      username: user.username,
      display_name: user.display_name,
      roles: user.roles,
      status: user.status
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
