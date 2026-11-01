defmodule ExGoCDWeb.AgentsChannelTest do
  use ExGoCDWeb.ChannelCase, async: false

  alias ExGoCDWeb.UserSocket

  test "the dashboard hears that the agent list changed" do
    {:ok, _reply, _channel} = join_dashboard()

    Phoenix.PubSub.broadcast(ExGoCD.PubSub, "agents:updates", {:agent_registered, %{uuid: "any"}})

    assert_push("agents_updated", %{})
  end

  test "noise on the same topic is not forwarded to the dashboard" do
    {:ok, _reply, _channel} = join_dashboard()

    Phoenix.PubSub.broadcast(ExGoCD.PubSub, "agents:updates", {:something_else, %{}})

    refute_receive %Phoenix.Socket.Message{event: "agents_updated"}, 100
  end

  defp join_dashboard do
    UserSocket
    |> socket("agents:updates", %{})
    |> subscribe_and_join("agents:updates", %{})
  end
end
