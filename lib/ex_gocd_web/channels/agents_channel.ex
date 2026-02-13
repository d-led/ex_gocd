# Copyright 2026 ex_gocd
# Phoenix channel for agents list updates. Subscribes to PubSub "agents:updates"
# and pushes to the client so the LiveView can refresh via a hook.

defmodule ExGoCDWeb.AgentsChannel do
  use Phoenix.Channel

  @topic "agents:updates"

  @impl true
  def join(@topic, _params, socket) do
    Phoenix.PubSub.subscribe(ExGoCD.PubSub, @topic)
    {:ok, socket}
  end

  @impl true
  def handle_info({event, _agent}, socket) when event in [:agent_registered, :agent_updated, :agent_enabled, :agent_disabled, :agent_deleted] do
    push(socket, "agents_updated", %{})
    {:noreply, socket}
  end
end
