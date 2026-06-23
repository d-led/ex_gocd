defmodule ExGoCDWeb.LiveSession do
  @moduledoc """
  on_mount hooks for the GoCD live_session.

  Assigns current_user and is_user_admin from session so all LiveViews
  under the :gocd live_session can use them for authorization and UI.

  Implements GoCD's "open mode": when no admin user is configured in the
  database, every user is treated as an administrator (full access). Once
  at least one admin-role user exists, normal role-based access control is
  enforced.
  """
  import Phoenix.Component

  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.User

  @doc "Assigns current_user, is_user_admin, and open_mode from session."
  def on_mount(:assign_current_user, _params, session, socket) do
    user = Accounts.get_current_user(session)

    is_user_admin =
      cond do
        # GoCD "open mode": no admin configured → everyone is admin
        not Accounts.admin_configured?() -> true
        # Explicit admin role
        User.has_role?(user, :admin) -> true
        true -> false
      end

    open_mode = not Accounts.admin_configured?()

    {:cont,
     socket
     |> assign_new(:current_user, fn -> user end)
     |> assign(:is_user_admin, is_user_admin)
     |> assign(:open_mode, open_mode)}
  end
end
