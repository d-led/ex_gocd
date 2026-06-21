defmodule ExGoCD.Accounts do
  @moduledoc """
  Account and current-user helpers for authorization backed by PostgreSQL.

  GoCD "open mode": when no admin user exists, the server grants full
  administrative access to all users. Once at least one admin user is
  configured, role-based access control is enforced.
  """
  import Ecto.Query, warn: false
  alias ExGoCD.Accounts.User
  alias ExGoCD.Accounts.PersonalAccessToken
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
    if System.get_env("USE_MOCK_DATA") == "true" do
      false
    else
      from(u in User, where: fragment("? @> ARRAY[?]::varchar[]", u.roles, "admin"))
      |> Repo.exists?()
    end
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

  @doc """
  Lists all active and revoked personal access tokens for a given user.
  """
  def list_user_tokens(user_id) do
    PersonalAccessToken
    |> where(user_id: ^user_id)
    |> Repo.all()
  end

  @doc """
  Gets a specific personal access token for a user.
  """
  def get_user_token(user_id, token_id) do
    Repo.get_by(PersonalAccessToken, id: token_id, user_id: user_id)
  end

  @doc """
  Generates and saves a new personal access token for a user.
  """
  def create_user_token(user_id, description) when is_binary(description) do
    # Generate 40-character secure random hex token
    raw_token = :crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)
    token_hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)

    attrs = %{
      user_id: user_id,
      description: description,
      token_hash: token_hash,
      revoked: false
    }

    case %PersonalAccessToken{} |> PersonalAccessToken.changeset(attrs) |> Repo.insert() do
      {:ok, token} ->
        token = Repo.preload(token, :user)
        {:ok, %{token | token: raw_token}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Revokes a personal access token.
  """
  def revoke_token(token, revoked_by, cause \\ nil) do
    attrs = %{
      revoked: true,
      revoked_at: DateTime.utc_now() |> DateTime.truncate(:second),
      revoked_by: revoked_by,
      revoke_cause: cause
    }

    token
    |> PersonalAccessToken.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Verifies a raw token value, updating its `last_used_at` timestamp if valid.
  """
  def verify_access_token(raw_token) when is_binary(raw_token) do
    token_hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)

    case Repo.get_by(PersonalAccessToken, token_hash: token_hash, revoked: false) do
      nil ->
        {:error, :invalid_token}

      token ->
        token = Repo.preload(token, :user)
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        {:ok, _} = token |> PersonalAccessToken.changeset(%{last_used_at: now}) |> Repo.update()
        {:ok, token.user}
    end
  end
end
