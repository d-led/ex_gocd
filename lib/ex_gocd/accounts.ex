defmodule ExGoCD.Accounts do
  @moduledoc """
  Account and current-user helpers for authorization.

  No login flow yet: `get_current_user/1` builds a user from session or
  returns a default (e.g. admin in dev). When auth is added, load the user
  from the DB here.
  """
  alias ExGoCD.Accounts.User

  @doc """
  Returns the current user from the session.

  Session keys used: `"user_id"`, `"username"`, `"roles"` (list of atoms).
  If session has no user, returns a default user (e.g. admin in dev) so
  policies can be exercised. Replace with real auth when needed.
  """
  @spec get_current_user(map()) :: User.t()
  def get_current_user(session) when is_map(session) do
    case {session["user_id"], session["username"], session["roles"]} do
      {nil, _, _} ->
        default_user()

      {id, username, roles} when is_list(roles) ->
        %User{
          id: id,
          username: username,
          roles: Enum.map(roles, &to_atom/1)
        }

      {id, username, _} ->
        %User{id: id, username: username, roles: []}
    end
  end

  def get_current_user(_), do: default_user()

  defp default_user do
    # No auth enabled: treat everyone as admin (matches original GoCD behavior).
    # When auth is added, return a non-admin guest here and set session on login.
    %User{
      id: nil,
      username: "guest",
      roles: [:admin]
    }
  end

  defp to_atom(x) when is_atom(x), do: x
  defp to_atom("admin"), do: :admin
  defp to_atom("user"), do: :user
  defp to_atom(_), do: :user
end
