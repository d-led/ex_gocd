defmodule ExGoCDWeb.API.UserController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.User
  alias ExGoCD.Repo

  @doc "GET /api/users"
  def index(conn, _params) do
    users = Repo.all(User)
    json(conn, %{users: Enum.map(users, &user_json/1)})
  end

  @doc "GET /api/users/:login"
  def show(conn, %{"login" => login}) do
    case Accounts.get_user_by_login(login) do
      nil ->
        conn |> put_status(:not_found) |> json(%{message: "User '#{login}' not found."})
      user ->
        json(conn, user_json(user))
    end
  end

  @doc "POST /api/users"
  def create(conn, %{"login" => login} = params) do
    case Accounts.create_user(%{
      login: login,
      email: params["email"],
      display_name: params["display_name"] || login,
      admin: Map.get(params, "admin", false)
    }) do
      {:ok, user} ->
        conn |> put_status(:created) |> json(user_json(user))
      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{message: "Failed to create user.", errors: format_errors(changeset)})
    end
  end

  @doc "PATCH /api/users/:login"
  def update(conn, %{"login" => login} = params) do
    case Accounts.get_user_by_login(login) do
      nil ->
        conn |> put_status(:not_found) |> json(%{message: "User '#{login}' not found."})
      user ->
        attrs = Map.take(params, ~w(email display_name admin))
        case Accounts.update_user(user, attrs) do
          {:ok, updated} -> json(conn, user_json(updated))
          {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{message: "Update failed.", errors: format_errors(changeset)})
        end
    end
  end

  @doc "DELETE /api/users/:login"
  def delete(conn, %{"login" => login}) do
    case Accounts.get_user_by_login(login) do
      nil ->
        conn |> put_status(:not_found) |> json(%{message: "User '#{login}' not found."})
      user ->
        Accounts.delete_user(user)
        json(conn, %{message: "User '#{login}' deleted."})
    end
  end

  defp user_json(user) do
    %{
      login: user.login,
      display_name: user.display_name,
      email: user.email,
      admin: user.admin,
      enabled: user.enabled
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
