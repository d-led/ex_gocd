defmodule ExGoCDWeb.API.CurrentUserController do
  @moduledoc """
  GoCD Current User API (api-current-user-v3): who is asking.
  """
  use ExGoCDWeb, :controller

  plug ExGoCDWeb.Plugs.RequireAuthenticatedUser

  @doc "GET /api/current_user"
  def show(conn, _params) do
    json(conn, present(conn.assigns.current_user))
  end

  # GoCD's user object: the login name, whether the account is usable, and the
  # links that lead to the rest of the user API. We model neither email nor
  # checkin aliases, so these come back as the documented empties.
  defp present(user) do
    %{
      _links: %{
        doc: %{href: "https://api.gocd.org/#users"},
        self: %{href: "/api/users/#{user.username}"},
        find: %{href: "/api/users/:login_name"}
      },
      login_name: user.username,
      display_name: user.display_name,
      enabled: user.status == "Active",
      email: nil,
      email_me: false,
      checkin_aliases: []
    }
  end
end
