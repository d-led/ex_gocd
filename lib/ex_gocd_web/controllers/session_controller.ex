defmodule ExGoCDWeb.SessionController do
  @moduledoc """
  Simple session-based authentication controller.
  Mimics GoCD's /go/auth/login form — users enter their username
  (no password in the simplified demo mode) and get a session cookie.
  When no admin is configured the login page still works but all pages
  are already open.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Accounts

  def new(conn, _params) do
    users = Accounts.list_users()
    render(conn, :new, users: users, error: nil)
  end

  def create(conn, %{"session" => %{"username" => username}}) when username != "" do
    case Accounts.get_user_by_username(username) do
      nil ->
        users = Accounts.list_users()
        render(conn, :new, users: users, error: "Unknown username: #{username}")

      user when user.status == "Active" ->
        conn
        |> put_session("username", user.username)
        |> put_session("user_id", user.id)
        |> put_flash(:info, "Signed in as #{user.display_name}")
        |> redirect(to: ~p"/")

      _disabled ->
        users = Accounts.list_users()
        render(conn, :new, users: users, error: "User #{username} is disabled.")
    end
  end

  def create(conn, _params) do
    users = Accounts.list_users()
    render(conn, :new, users: users, error: "Please enter a username.")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/")
  end
end
