defmodule ExGoCDWeb.Plugs.RequireAuthenticatedUser do
  @moduledoc """
  Halts with 401 unless the session names a real user, and assigns that user as
  `:current_user`.

  GoCD's open mode hands an anonymous caller a guest user with no id, so a
  missing id is what tells the two apart.
  """
  import Plug.Conn

  alias ExGoCD.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user = Accounts.get_current_user(get_session(conn))

    if is_nil(user.id) do
      conn
      |> put_status(:unauthorized)
      |> Phoenix.Controller.json(%{error: "Unauthorized"})
      |> halt()
    else
      assign(conn, :current_user, user)
    end
  end
end
