defmodule ExGoCDWeb.AgentChannelTest do
  use ExGoCDWeb.ChannelCase, async: false

  alias ExGoCD.Agents
  alias ExGoCDWeb.AgentChannel
  alias ExGoCDWeb.AgentSocket

  @uuid "550e8400-e29b-41d4-a716-4466554401a1"
  @disabled_uuid "550e8400-e29b-41d4-a716-4466554401a2"

  describe "joining" do
    test "an agent joins and the connection knows which agent it is" do
      register_agent(@uuid, "channel-agent")

      {:ok, _reply, channel} = join_agent(@uuid, "channel-agent")

      assert channel.assigns.agent_uuid == @uuid
    end

    test "a disabled agent is refused, and told why" do
      register_agent(@disabled_uuid, "disabled-agent")
      {:ok, _agent} = Agents.disable_agent(@disabled_uuid)

      assert {:error, %{reason: "agent is disabled"}} =
               AgentSocket
               |> socket("agent:" <> @disabled_uuid, %{})
               |> subscribe_and_join("agent", %{"uuid" => @disabled_uuid, "hostName" => "x"})
    end
  end

  describe "talking to the agent" do
    test "a ping is answered and the agent is kept alive" do
      register_agent(@uuid, "channel-agent")
      {:ok, _reply, channel} = join_agent(@uuid, "channel-agent")

      ref = push(channel, "ping", %{"agentRuntimeInfo" => %{"runtimeStatus" => "Idle"}})

      assert_reply ref, :ok, %{}
      assert %{hostname: "channel-agent"} = Agents.get_agent_by_uuid(@uuid)
    end

    test "cancelling a build reaches the agent that runs it" do
      register_agent(@uuid, "channel-agent")
      {:ok, _reply, _channel} = join_agent(@uuid, "channel-agent")

      :ok = AgentChannel.request_cancel_build(@uuid, "build-that-must-stop")

      assert_push("cancelBuild", %{"buildId" => "build-that-must-stop"})
    end

    test "a build sent to the agent's topic reaches the agent" do
      register_agent(@uuid, "channel-agent")
      {:ok, _reply, _channel} = join_agent(@uuid, "channel-agent")

      Phoenix.PubSub.broadcast(
        ExGoCD.PubSub,
        "agent:" <> @uuid,
        {:build, %{"buildId" => "job-1"}}
      )

      assert_push("build", %{"buildId" => "job-1"})
    end
  end

  defp register_agent(uuid, hostname) do
    {:ok, agent} =
      Agents.register_agent(%{uuid: uuid, hostname: hostname, ipaddress: "127.0.0.1"})

    agent
  end

  defp join_agent(uuid, hostname) do
    AgentSocket
    |> socket("agent:" <> uuid, %{})
    |> subscribe_and_join("agent", %{"uuid" => uuid, "hostName" => hostname})
  end
end
