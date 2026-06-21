defmodule ExGoCD.Policies do
  @moduledoc """
  Authorization helpers. Policy modules implement authorize/3; this module
  provides permit?/3 for use in LiveView and controllers.
  """
  @doc """
  Returns true if the policy allows the action for the user, false otherwise.
  """
  def permit?(policy_module, action, user, params \\ []) do
    params = if Keyword.keyword?(params), do: Map.new(params), else: params
    case policy_module.authorize(action, user, params) do
      :ok -> true
      _ -> false
    end
  end
end
