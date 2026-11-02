defmodule ExGoCD.AgentRegistryTest do
  @moduledoc """
  The registry decides whether a test job can be sent: it asks Presence whether the
  agent has a connection, and only then builds a payload, records the run and
  broadcasts the build. No test reached it, so none of that was checked.

  The registry is a cluster singleton running on its own, so this runs
  synchronously: it is the shared connection that lets that process query.
  """
  use ExGoCD.DataCase, async: false

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.AgentRegistry
  alias ExGoCD.Agents
  alias ExGoCD.Repo
  alias ExGoCDWeb.AgentPresence

  @topic "agent"
  @uuid "550e8400-e29b-41d4-a716-446655540001"

  setup do
    {:ok, _agent} =
      Agents.register_agent(%{uuid: @uuid, hostname: "registry-agent", ipaddress: "10.0.0.7"})

    :ok
  end

  describe "connected?/1" do
    test "is false for an agent that never connected" do
      refute AgentRegistry.connected?(@uuid)
    end

    test "is true once presence has the agent" do
      track(@uuid)

      assert AgentRegistry.connected?(@uuid)
    end
  end

  describe "request_test_job/1" do
    test "an agent that is not connected is told so, and nothing is recorded" do
      assert AgentRegistry.request_test_job(@uuid) == {:error, :agent_not_connected}
      assert run_count() == 0
    end

    test "a connected agent is sent a build for the job it asked about" do
      track(@uuid)
      ExGoCD.PubSub |> Phoenix.PubSub.subscribe("agent:" <> @uuid)

      assert AgentRegistry.request_test_job(@uuid) == :ok

      assert_receive {:build, payload}, 2_000
      assert payload["buildId"] =~ "test-job-"
      assert payload["buildLocator"] == "test-pipeline/1/test-stage/1/test-job/1"
      assert payload["buildCommand"]["command"] == "echo"
      assert payload["consoleURI"] =~ "/api/builds/#{payload["buildId"]}/console"

      assert [%AgentJobRun{build_id: build_id}] = runs()
      assert build_id == payload["buildId"]
    end

    test "something that is not a uuid is rejected without touching presence" do
      assert AgentRegistry.request_test_job(42) == {:error, :invalid_uuid}
      assert AgentRegistry.request_test_job(nil) == {:error, :invalid_uuid}
    end
  end

  defp track(uuid) do
    {:ok, _} = AgentPresence.track(self(), @topic, uuid, %{})
    on_exit(fn -> AgentPresence.untrack(self(), @topic, uuid) end)
  end

  defp runs do
    Repo.all(from r in AgentJobRun, where: r.agent_uuid == ^@uuid)
  end

  defp run_count do
    AgentJobRuns.list_runs_for_agent(@uuid) |> length()
  end
end
