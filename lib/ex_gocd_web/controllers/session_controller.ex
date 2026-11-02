defmodule ExGoCDWeb.SessionController do
  @moduledoc """
  Session-based authentication controller.

  Mirrors GoCD's /go/auth/login flow. When no admin user is configured
  (open mode), all pages are already accessible without signing in.
  Once at least one admin user exists (security mode), users must sign
  in to access admin functions.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Accounts

  def new(conn, params) do
    users = Accounts.list_users()
    render(conn, :new, users: users, error: nil, return_to: params["return_to"])
  end

  def create(conn, %{"session" => %{"username" => username}} = params) when username != "" do
    case Accounts.get_user_by_username(username) do
      nil ->
        users = Accounts.list_users()

        render(conn, :new,
          users: users,
          error: "Unknown username: #{username}",
          return_to: params["return_to"]
        )

      user when user.status == "Active" ->
        conn
        |> put_session("username", user.username)
        |> put_session("user_id", user.id)
        |> put_flash(:info, "Signed in as #{user.display_name}")
        |> redirect(to: return_to(params))

      _disabled ->
        users = Accounts.list_users()

        render(conn, :new,
          users: users,
          error: "User #{username} is disabled.",
          return_to: params["return_to"]
        )
    end
  end

  def create(conn, params) do
    users = Accounts.list_users()

    render(conn, :new,
      users: users,
      error: "Please enter a username.",
      return_to: params["return_to"]
    )
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/")
  end

  # Where to go after signing in. The MCP authorization step sends a reader here
  # and expects them back; the value must stay on this host, so anything that is
  # not a single-slash path is ignored rather than followed.
  defp return_to(%{"return_to" => path}) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//"),
      do: path,
      else: ~p"/"
  end

  defp return_to(_params), do: ~p"/"
end
