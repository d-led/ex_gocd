# Copyright 2026 ex_gocd
# GoCD agent WebSocket protocol: messages are JSON with "action" and "data" (and optional "ackId" / "messageId").
# This serializer converts between Phoenix.Socket.Message and GoCD format for compatibility with GoCD agents.

defmodule ExGoCDWeb.AgentSerializer do
  @behaviour Phoenix.Socket.Serializer

  @doc """
  Decodes a GoCD-format JSON frame into a Phoenix.Socket.Message.

  GoCD format: `{"action": "join" | "ping", "data": {...}, "ackId": "..."}` (ackId optional).
  First message from agent must be "join" so the channel is established; "ping" is used for heartbeats.
  """
  def decode!(raw, _opts) do
    payload = Phoenix.json_library().decode!(raw)

    action = payload["action"]
    data = payload["data"] || %{}
    ack_id = payload["ackId"] || payload["messageId"]

    # Only "join" establishes the channel; "ping" and others are handle_in events (avoids duplicate-join phx_close)
    event = if action == "join", do: "phx_join", else: action

    # Wrap data so channel receives a map (identifier for join, or raw data for other events)
    payload_map =
      if event == "phx_join" do
        %{"identifier" => data}
      else
        Map.put(data || %{}, "ackId", ack_id)
      end

    ref = ack_id || "1"

    %Phoenix.Socket.Message{
      topic: "agent",
      event: event,
      payload: payload_map,
      ref: ref
    }
  end

  @doc """
  Encodes Phoenix.Socket.Message or Reply to GoCD-format JSON.

  Push: event "setCookie" with payload -> {"action": "setCookie", "data": ...}
  phx_reply: sent as {"action": "phx_reply", "data": {}} so agent can ignore it.
  """
  def encode!(%Phoenix.Socket.Reply{status: :ok, payload: payload}) do
    # Join success; agent expects setCookie from channel push, so we send phx_reply in GoCD shape (agent ignores)
    json = Phoenix.json_library().encode!(%{"action" => "phx_reply", "data" => payload || %{}})
    {:socket_push, :text, json}
  end

  def encode!(%Phoenix.Socket.Reply{status: :error, payload: payload}) do
    json =
      Phoenix.json_library().encode!(%{
        "action" => "phx_reply",
        "data" => %{"status" => "error", "response" => payload}
      })

    {:socket_push, :text, json}
  end

  def encode!(%Phoenix.Socket.Message{event: event, payload: payload, ref: ref}) do
    # GoCD format: action, data; optional messageId for acks (setCookie sends data as string)
    data =
      cond do
        is_binary(payload) -> payload
        is_map(payload) -> payload
        true -> payload || %{}
      end

    map = %{"action" => event, "data" => data}
    map = if ref && ref != "", do: Map.put(map, "messageId", ref), else: map
    json = Phoenix.json_library().encode!(map)
    {:socket_push, :text, json}
  end

  def fastlane!(%Phoenix.Socket.Broadcast{event: event, payload: payload}) do
    map = %{"action" => event, "data" => payload || %{}}
    json = Phoenix.json_library().encode!(map)
    {:socket_push, :text, json}
  end
end
