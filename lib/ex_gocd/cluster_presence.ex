defmodule ExGoCD.ClusterPresence do
  @moduledoc """
  Phoenix Presence for cluster state. Tracks nodes and their singleton locations.

  Each node tracks itself with metadata: %{singletons: %{Module => node_string}}.
  Presence handles joins/leaves/crashes automatically via CRDT with timeout.
  """
  use Phoenix.Presence,
    otp_app: :ex_gocd,
    pubsub_server: ExGoCD.PubSub
end
