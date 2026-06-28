defmodule ExGoCD.Plugin.NotificationSink do
  @moduledoc """
  Custom notification delivery channel. Slack, Teams, webhook, etc.
  """

  @callback deliver(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  @callback validate_config(keyword()) :: :ok | {:error, String.t()}
end
