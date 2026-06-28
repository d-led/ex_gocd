defmodule RedactIntegrationHelper do
  @moduledoc false
  use GenServer
  use ExGoCD.GenServerRedact

  @impl true
  def init(state), do: {:ok, state}
end
