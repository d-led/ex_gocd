defmodule ExGoCDWeb.LiveSession do
  @moduledoc """
  on_mount hooks for the GoCD live_session.

  Assigns current_user and is_user_admin from session so all LiveViews
  under the :gocd live_session can use them for authorization and UI.
  """
  import Phoenix.Component

  alias ExGoCD.Accounts
  alias ExGoCD.Policies.AgentPolicy

  @doc "Assigns current_user and is_user_admin from session."
  def on_mount(:assign_current_user, _params, session, socket) do
    user = Accounts.get_current_user(session)
    is_user_admin = ExGoCD.Policies.permit?(AgentPolicy, :manage_agents, user)

    {:cont,
     socket
     |> assign_new(:current_user, fn -> user end)
     |> assign(:is_user_admin, is_user_admin)}
  end
end
