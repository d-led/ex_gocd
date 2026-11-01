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
  def handle_info({event, _agent}, socket)
      when event in [
             :agent_registered,
             :agent_updated,
             :agent_enabled,
             :agent_disabled,
             :agent_deleted
           ] do
    push(socket, "agents_updated", %{})
    {:noreply, socket}
  end

  # Anything else on this topic is not ours to act on. Ignoring it keeps the
  # dashboard's subscription alive; a missing clause would take the channel
  # down and stop live updates until the page is reloaded.
  def handle_info(_message, socket) do
    {:noreply, socket}
  end
end
