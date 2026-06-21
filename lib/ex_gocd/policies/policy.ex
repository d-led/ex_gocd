defmodule ExGoCD.Policies.Policy do
  @moduledoc """
  Behaviour for authorization policies. Implement authorize/3; use
  ExGoCD.Policies.permit?/3 to check from LiveView/controllers.
  """
  @type action :: atom() | String.t()
  @type auth_result :: :ok | :error | {:error, reason :: any()} | true | false

  @callback authorize(action :: action, user :: any(), params :: map() | any()) :: auth_result
end
