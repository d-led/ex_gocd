defmodule ExGoCDWeb.AgentSerializerTest do
  use ExUnit.Case, async: true

  alias ExGoCDWeb.AgentSerializer

  describe "a frame from the agent" do
    test "a join becomes the channel's join, carrying who the agent is" do
      message =
        decode(~s({"action":"join","data":{"uuid":"agent-1","cookie":"secret"}}))

      assert message.event == "phx_join"
      assert message.topic == "agent"
      assert message.payload == %{"identifier" => %{"uuid" => "agent-1", "cookie" => "secret"}}
    end

    test "a ping stays a ping, and keeps the id the agent will match the answer to" do
      message = decode(~s({"action":"ping","ackId":"42","data":{"runtimeStatus":"Idle"}}))

      assert message.event == "ping"
      assert message.payload == %{"runtimeStatus" => "Idle", "ackId" => "42"}
      assert message.ref == "42"
    end

    test "a ping without an id still has one, so the channel can answer it" do
      assert %Phoenix.Socket.Message{ref: "1"} = decode(~s({"action":"ping"}))
    end
  end

  describe "a frame to the agent" do
    test "a push names the action the agent is listening for" do
      assert {:socket_push, :text, json} =
               AgentSerializer.encode!(%Phoenix.Socket.Message{
                 topic: "agent",
                 event: "setCookie",
                 payload: %{"cookie" => "abc"},
                 ref: "7"
               })

      assert Jason.decode!(json) == %{
               "action" => "setCookie",
               "data" => %{"cookie" => "abc"},
               "messageId" => "7"
             }
    end

    test "the answer to a join is phrased as a reply the agent ignores" do
      assert {:socket_push, :text, json} =
               AgentSerializer.encode!(%Phoenix.Socket.Reply{
                 status: :ok,
                 payload: %{"joined" => true},
                 ref: "1",
                 topic: "agent"
               })

      assert Jason.decode!(json) == %{"action" => "phx_reply", "data" => %{"joined" => true}}
    end

    test "a refused join says so" do
      assert {:socket_push, :text, json} =
               AgentSerializer.encode!(%Phoenix.Socket.Reply{
                 status: :error,
                 payload: %{"reason" => "agent is disabled"},
                 ref: "1",
                 topic: "agent"
               })

      assert Jason.decode!(json) == %{
               "action" => "phx_reply",
               "data" => %{
                 "status" => "error",
                 "response" => %{"reason" => "agent is disabled"}
               }
             }
    end

    test "a broadcast reaches the agent in the same shape as a push" do
      assert {:socket_push, :text, json} =
               AgentSerializer.fastlane!(%Phoenix.Socket.Broadcast{
                 topic: "agent",
                 event: "build",
                 payload: %{"buildId" => "job-1"}
               })

      assert Jason.decode!(json) == %{"action" => "build", "data" => %{"buildId" => "job-1"}}
    end
  end

  defp decode(raw), do: AgentSerializer.decode!(raw, [])
end
