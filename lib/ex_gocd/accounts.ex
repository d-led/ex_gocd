defmodule ExGoCD.Accounts do
  @moduledoc """
  Account and current-user helpers for authorization backed by PostgreSQL.

  GoCD "open mode": when no admin user exists, the server grants full
  administrative access to all users. Once at least one admin user is
  configured, role-based access control is enforced.
  """
  import Ecto.Query, warn: false
  alias ExGoCD.Accounts.User
  alias ExGoCD.Repo

  @doc """
  Returns all users ordered by username.
  """
  def list_users do
    User
    |> order_by(asc: :username)
    |> Repo.all()
  end

  @doc """
  Retrieves a user by ID.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Retrieves a user by username.
  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end
  def get_user_by_username(_), do: nil

  @doc """
  Creates a user.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an %Ecto.Changeset{} for tracking user changes.
  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc """
  Returns true if at least one admin user exists — meaning GoCD's "security
  mode" is active. When false, the system is in "open mode" and everyone
  has administrative access.
  """
  @spec admin_configured?() :: boolean()
  def admin_configured? do
    from(u in User, where: fragment("? @> ARRAY[?]::varchar[]", u.roles, "admin"))
    |> Repo.exists?()
  end

  @doc """
  Returns the current user from the session, loading from the DB when available.
  """
  @spec get_current_user(map()) :: User.t()
  def get_current_user(session) when is_map(session) do
    username = session["username"]

    case get_user_by_username(username) do
      nil ->
        # Fallback to session values if user is not in DB (or DB is empty)
        case {session["user_id"], session["username"], session["roles"]} do
          {nil, _, _} ->
            default_user()

          {id, name, roles} when is_list(roles) ->
            %User{
              id: id,
              username: name,
              display_name: name,
              roles: Enum.map(roles, &to_string/1),
              status: "Active"
            }

          {id, name, _} ->
            %User{
              id: id,
              username: name,
              display_name: name,
              roles: [],
              status: "Active"
            }
        end

      %User{} = user ->
        if user.status == "Active" do
          user
        else
          # Disabled user: empty roles
          %{user | roles: []}
        end
    end
  end

  def get_current_user(_), do: default_user()

  defp default_user do
    # GoCD open mode: if no admin user is configured, any unauthenticated
    # visitor gets full admin access. Once an admin exists, unauthenticated
    # guests have no roles (viewer only).
    if admin_configured?() do
      %User{
        id: nil,
        username: "guest",
        display_name: "Guest Viewer",
        roles: [],
        status: "Active"
      }
    else
      %User{
        id: nil,
        username: "guest",
        display_name: "Guest Admin",
        roles: ["admin"],
        status: "Active"
      }
    end
  end
end
