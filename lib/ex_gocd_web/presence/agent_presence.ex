# Copyright 2026 ex_gocd
# Phoenix Presence for agent WebSocket connections.
# Tracks which agents are connected; when the channel process exits (disconnect/crash),
# Presence automatically removes the entry so we get connection loss for free.

defmodule ExGoCDWeb.AgentPresence do
  use Phoenix.Presence,
    otp_app: :ex_gocd,
    pubsub_server: ExGoCD.PubSub
end
