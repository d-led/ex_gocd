# Copyright 2026 ex_gocd
# WebSocket socket for GoCD agents. Uses custom serializer for GoCD protocol (action/data JSON).
# Compatible with original GoCD agent protocol: /agent-websocket, setCookie, ping, build, etc.

defmodule ExGoCDWeb.AgentSocket do
  use Phoenix.Socket

  channel "agent", ExGoCDWeb.AgentChannel

  @impl Phoenix.Socket
  def connect(_params, socket, _connect_info) do
    # Agents connect after registering via POST /admin/agent; no auth at WebSocket level
    {:ok, socket}
  end

  @impl Phoenix.Socket
  def id(socket) do
    # Optional: use agent uuid from assigns once we get it from first ping
    case socket.assigns do
      %{agent_uuid: uuid} when is_binary(uuid) -> "agent:#{uuid}"
      _ -> nil
    end
  end
end
