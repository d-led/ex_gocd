defmodule ExGoCD.Policies.PipelineGroupPolicy do
  @moduledoc """
  Authorization policy for pipeline group operations.

  GoCD parity: delegate admin/operator/viewer per pipeline group.
  Users with a group role can operate pipelines in that group.
  Global admins always have access.
  """
  @behaviour ExGoCD.Policies.Policy

  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.User

  @impl true
  def authorize(:operate_pipeline, %User{} = user, %{pipeline_group: group}) do
    if Accounts.can_access_pipeline_group?(user, group, "operator") do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def authorize(:admin_pipeline, %User{} = user, %{pipeline_group: group}) do
    if Accounts.can_access_pipeline_group?(user, group, "admin") do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def authorize(:view_pipeline, %User{} = user, %{pipeline_group: group}) do
    if Accounts.can_access_pipeline_group?(user, group, "viewer") do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def authorize(_action, _user, _params), do: {:error, :unknown_action}
end
