defmodule ExGoCD.Policies.EnvironmentPolicy do
  @moduledoc """
  Authorization policy for environment management and pipeline triggering.
  """
  @behaviour ExGoCD.Policies.Policy

  alias ExGoCD.Accounts.User

  @impl true
  def authorize(:manage_environments, %User{} = user, _params) do
    if User.has_role?(user, :admin), do: :ok, else: {:error, :forbidden}
  end

  def authorize(:view_environments, %User{} = user, _params) do
    if User.has_role?(user, :admin) or User.has_role?(user, :developer) or
         User.has_role?(user, :viewer) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def authorize(:trigger_pipeline, %User{} = user, _params) do
    if User.has_role?(user, :admin) or User.has_role?(user, :developer) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def authorize(_action, _user, _params), do: {:error, :unknown_action}
end
