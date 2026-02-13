# Copyright 2026 ex_gocd
# Channel for GoCD agent WebSocket. Handles ping (heartbeat), setCookie on join, and future build/reregister/cancelBuild.

defmodule ExGoCDWeb.AgentChannel do
  use Phoenix.Channel

  @doc """
  Agent joins with first "ping" (decoded by serializer as phx_join). We send setCookie so the agent
  can use it for subsequent requests. GoCD protocol: server sends setCookie after connection.
  """
  @impl Phoenix.Channel
  def join("agent", %{"identifier" => identifier} = params, socket) do
    uuid =
      get_in(identifier, ["uuid"]) || get_in(identifier, ["identifier", "uuid"]) || params["uuid"]

    socket = assign(socket, :agent_uuid, uuid)
    socket = assign(socket, :agent_identifier, identifier)

    # GoCD protocol: server sends setCookie; agent stores it and sends in future pings
    cookie = generate_cookie()
    push(socket, "setCookie", cookie)

    {:ok, socket}
  end

  def join("agent", _params, socket) do
    cookie = generate_cookie()
    push(socket, "setCookie", cookie)
    {:ok, socket}
  end

  @impl Phoenix.Channel
  def handle_in("ping", %{"identifier" => _}, socket) do
    # Heartbeat: agent sends runtime info; we can update last_seen in DB later
    # For now just allow; agent may send ackId for the message we sent (e.g. setCookie)
    {:noreply, socket}
  end

  def handle_in("acknowledge", %{"ackId" => _ack_id}, socket) do
    # Agent ACK for a message we sent; no action needed for now
    {:noreply, socket}
  end

  def handle_in(event, payload, socket) do
    # Log unknown events for protocol compatibility debugging
    require Logger
    Logger.debug("AgentChannel unknown event=#{inspect(event)} payload=#{inspect(payload)}")
    {:noreply, socket}
  end

  defp generate_cookie do
    # Simple session cookie; could be tied to agent uuid and stored in DB
    Base.encode64(:crypto.strong_rand_bytes(24))
  end
end
