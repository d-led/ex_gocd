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
  alias ExGoCD.Accounts.PipelineGroupPermission
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

  # ── Pipeline Group Permissions ──────────────────────────────────────────

  @doc """
  Grants a role on a pipeline group to a user.
  Valid roles: `"viewer"`, `"operator"`, `"admin"`.
  """
  @spec grant_pipeline_group_permission(integer(), String.t(), String.t()) :: {:ok, PipelineGroupPermission.t()} | {:error, Ecto.Changeset.t()}
  def grant_pipeline_group_permission(user_id, pipeline_group, role) do
    %PipelineGroupPermission{}
    |> PipelineGroupPermission.changeset(%{user_id: user_id, pipeline_group: pipeline_group, role: role})
    |> Repo.insert(on_conflict: :replace_all, conflict_target: [:user_id, :pipeline_group])
  end

  @doc """
  Revokes a pipeline group permission.
  """
  def revoke_pipeline_group_permission(user_id, pipeline_group) do
    case Repo.get_by(PipelineGroupPermission, user_id: user_id, pipeline_group: pipeline_group) do
      nil -> {:error, :not_found}
      perm -> Repo.delete(perm)
    end
  end

  @doc """
  Lists all pipeline group permissions for a user.
  """
  def list_pipeline_group_permissions(user_id) do
    PipelineGroupPermission
    |> where(user_id: ^user_id)
    |> Repo.all()
  end

  @doc """
  Checks if a user has a minimum role (or higher) on a pipeline group.
  Role hierarchy: admin > operator > viewer.

  Returns true if the user is a global admin or has sufficient group permission.
  """
  @spec can_access_pipeline_group?(User.t(), String.t(), String.t()) :: boolean()
  def can_access_pipeline_group?(%User{} = user, pipeline_group, required_role \\ "viewer") do
    # Global admins can access everything
    if User.has_role?(user, :admin) do
      true
    else
      # Guest users (nil id) have no permissions
      if is_nil(user.id) do
        false
      else
        perm = Repo.get_by(PipelineGroupPermission, user_id: user.id, pipeline_group: pipeline_group)

        case perm do
          nil -> false
          %{role: role} -> role_sufficient?(role, required_role)
        end
      end
    end
  end

  defp role_sufficient?("admin", _), do: true
  defp role_sufficient?("operator", "admin"), do: false
  defp role_sufficient?("operator", _), do: true
  defp role_sufficient?("viewer", "viewer"), do: true
  defp role_sufficient?(_, _), do: false
end
