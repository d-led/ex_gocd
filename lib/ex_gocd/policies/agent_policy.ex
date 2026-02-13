defmodule ExGoCD.Policies.AgentPolicy do
  @moduledoc """
  Authorization policy for agent management.

  Mirrors GoCD's isUserAdmin: only users with :admin (or equivalent) can
  enable/disable/delete agents, use bulk actions, and see the job run history link.
  """
  @behaviour ExGoCD.Policies.Policy

  alias ExGoCD.Accounts.User

  @impl true
  def authorize(:manage_agents, %User{roles: roles}, _params) do
    if :admin in roles, do: :ok, else: {:error, :forbidden}
  end

  def authorize(_action, _user, _params), do: {:error, :unknown_action}
end
