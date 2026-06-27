defmodule ExGoCD.RedactTestServer do
  @moduledoc false
  use GenServer
  use ExGoCD.GenServerRedact

  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  def init(state), do: {:ok, state}
end
