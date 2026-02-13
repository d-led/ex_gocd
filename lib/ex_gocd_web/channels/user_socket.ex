# Copyright 2026 ex_gocd
# Web socket for browser clients (agents list and other UI channels).

defmodule ExGoCDWeb.UserSocket do
  use Phoenix.Socket

  channel "agents:updates", ExGoCDWeb.AgentsChannel

  @impl Phoenix.Socket
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl Phoenix.Socket
  def id(_socket), do: nil
end
