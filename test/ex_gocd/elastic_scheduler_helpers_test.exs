defmodule ExGoCD.ElasticSchedulerHelpersTest do
  @moduledoc """
  The elastic schedulers ask these helpers whether a pending job still needs an
  agent to be provisioned for it. Answering "no" wrongly leaves the job waiting
  for an agent that will never come, so the answers have to be the ones the
  scheduler itself assigns by.
  """
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Agents
  alias ExGoCD.ElasticSchedulerHelpers
  alias ExGoCD.Scheduler

  setup do
    Scheduler.clear_queue()
    :ok
  end

  describe "needs_elastic_agent?/1" do
    test "an idle agent with the job's resources can handle it" do
      idle_agent(resources: ["linux"])

      refute ElasticSchedulerHelpers.needs_elastic_agent?(job(resources: ["LINUX"]))
    end

    test "an idle agent without the job's resources cannot" do
      idle_agent(resources: ["windows"])

      assert ElasticSchedulerHelpers.needs_elastic_agent?(job(resources: ["linux"]))
    end

    test "a job with no environments is not handled by an agent that belongs to one" do
      idle_agent(environments: ["staging"])

      assert ElasticSchedulerHelpers.needs_elastic_agent?(job())
    end

    test "a job is handled by an agent in one of its environments, in any case" do
      idle_agent(environments: ["Production"])

      refute ElasticSchedulerHelpers.needs_elastic_agent?(job(environments: ["production"]))
    end

    test "a job pinned to an idle agent is not elastic" do
      uuid = idle_agent()

      refute ElasticSchedulerHelpers.needs_elastic_agent?(job(agent_uuid: uuid))
    end

    test "a job pinned to an agent that is not there is elastic" do
      idle_agent()

      assert ElasticSchedulerHelpers.needs_elastic_agent?(job(agent_uuid: Ecto.UUID.generate()))
    end

    test "no agent at all means the job is elastic" do
      assert ElasticSchedulerHelpers.needs_elastic_agent?(job())
    end
  end

  describe "idle_too_long?/2" do
    test "an agent idle beyond the timeout has been idle too long" do
      uuid = idle_agent()

      assert ElasticSchedulerHelpers.idle_too_long?(%{agent_uuid: uuid}, -1)
    end

    test "an agent idle within the timeout has not" do
      uuid = idle_agent()

      refute ElasticSchedulerHelpers.idle_too_long?(%{agent_uuid: uuid}, 100_000)
    end

    test "an agent that never registered is timed out after ten minutes" do
      long_ago = DateTime.add(DateTime.utc_now(), -700, :second)
      just_now = DateTime.add(DateTime.utc_now(), -60, :second)

      assert ElasticSchedulerHelpers.idle_too_long?(%{created_at: long_ago})
      refute ElasticSchedulerHelpers.idle_too_long?(%{created_at: just_now})
    end
  end

  describe "job_name/1" do
    test "names the job from either spelling of the key" do
      assert ElasticSchedulerHelpers.job_name(%{job: "compile"}) == "compile"
      assert ElasticSchedulerHelpers.job_name(%{"job" => "compile"}) == "compile"
      assert ElasticSchedulerHelpers.job_name(%{}) == "unknown"
    end
  end

  describe "log_event/4" do
    test "puts the newest event first and keeps only the last few" do
      state = %{events: []}

      state =
        Enum.reduce(1..3, state, fn n, state ->
          ElasticSchedulerHelpers.log_event(state, :info, "event #{n}", 2)
        end)

      assert Enum.map(state.events, & &1.message) == ["event 3", "event 2"]
    end
  end

  defp job(attrs \\ []) do
    %{
      job: "compile",
      resources: Keyword.get(attrs, :resources, []),
      environments: Keyword.get(attrs, :environments, []),
      agent_uuid: Keyword.get(attrs, :agent_uuid)
    }
  end

  defp idle_agent(attrs \\ []) do
    uuid = Ecto.UUID.generate()

    {:ok, _} =
      Agents.register_agent(%{
        uuid: uuid,
        hostname: "elastic-#{System.unique_integer([:positive])}",
        ipaddress: "127.0.0.1",
        resources: Keyword.get(attrs, :resources, []),
        environments: Keyword.get(attrs, :environments, [])
      })

    uuid
  end
end
