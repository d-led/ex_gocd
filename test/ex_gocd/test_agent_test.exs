# Copyright 2026 ex_gocd
# Unit tests for ExGoCD.TestAgent.

defmodule ExGoCD.TestAgentTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Agents
  alias ExGoCD.TestAgentSupervisor
  alias ExGoCD.Scheduler
  alias ExGoCD.AgentJobRuns
  alias ExGoCDWeb.AgentPresence

  setup do
    # Wait for Scheduler GenServer to be alive if it restarted
    wait_for_scheduler()
    # Clear scheduler queue
    Scheduler.clear_queue()
    # Remove any mock agents from presence
    TestAgentSupervisor.stop_all_agents()

    # Create a unique uuid for test
    uuid = ExGoCD.TestAgent.UUID.uuid4()

    # Start the test agent
    {:ok, pid} = TestAgentSupervisor.start_agent(
      uuid: uuid,
      ping_interval: 2000,
      work_simulation_ms: 100
    )

    on_exit(fn ->
      TestAgentSupervisor.stop_all_agents()
    end)

    %{uuid: uuid, pid: pid}
  end

  test "agent registers in the database and presence", %{uuid: uuid} do
    # Verify agent exists in DB
    agent = Agents.get_agent_by_uuid(uuid)
    assert agent
    assert agent.hostname =~ "mock-agent-"
    assert agent.disabled == false

    # Verify agent is tracked in Presence
    assert Map.has_key?(AgentPresence.list("agent"), uuid)

    # Clean up synchronously
    TestAgentSupervisor.stop_all_agents()
  end

  test "agent pings and executes scheduled jobs to completion", %{uuid: uuid} do
    # Verify starting state
    agent = Agents.get_agent_by_uuid(uuid)
    assert agent.state == "Idle"

    # Enqueue a job matching this agent
    {:ok, _job_id} = Scheduler.schedule_job(%{
      pipeline: "test-pipeline",
      stage: "test-stage",
      job: "test-job"
    })

    # Trigger try_assign_work manually or wait for ping heartbeat
    Scheduler.try_assign_work(uuid)

    # Agent should receive the job, update status in DB to Building
    assert_receive_or_retry(5, fn ->
      updated_agent = Agents.get_agent_by_uuid(uuid)
      updated_agent.state == "Building"
    end)

    # Check that a run was created
    runs = AgentJobRuns.list_runs_for_agent(uuid)
    assert length(runs) == 1
    run = List.first(runs)
    assert run.pipeline_name == "test-pipeline"

    # Wait for the agent to finish execution (Preparing -> Building -> Completed)
    assert_receive_or_retry(10, fn ->
      updated_agent = Agents.get_agent_by_uuid(uuid)
      latest_run = List.first(AgentJobRuns.list_runs_for_agent(uuid))
      updated_agent.state == "Idle" and latest_run.state == "Completed" and latest_run.result == "Passed"
    end)

    # Clean up synchronously
    TestAgentSupervisor.stop_all_agents()
  end

  test "agent handles job cancellation", %{uuid: uuid} do
    # Enqueue a job matching this agent
    {:ok, _job_id} = Scheduler.schedule_job(%{
      pipeline: "test-pipeline",
      stage: "test-stage",
      job: "test-job"
    })

    Scheduler.try_assign_work(uuid)

    # Wait for execution to start
    assert_receive_or_retry(5, fn ->
      Agents.get_agent_by_uuid(uuid).state == "Building"
    end)

    [run] = AgentJobRuns.list_runs_for_agent(uuid)

    # Cancel the build
    :ok = ExGoCDWeb.AgentChannel.request_cancel_build(uuid, run.build_id)

    # Agent should transition to Idle and report Cancelled
    assert_receive_or_retry(10, fn ->
      updated_agent = Agents.get_agent_by_uuid(uuid)
      latest_run = List.first(AgentJobRuns.list_runs_for_agent(uuid))
      updated_agent.state == "Idle" and latest_run.state == "Completed" and latest_run.result == "Cancelled"
    end)

    # Clean up synchronously
    TestAgentSupervisor.stop_all_agents()
  end

  # Helper to poll condition periodically
  defp assert_receive_or_retry(retries, func) do
    if func.() do
      true
    else
      if retries > 0 do
        Process.sleep(50)
        assert_receive_or_retry(retries - 1, func)
      else
        flunk("Assertion failed after retries")
      end
    end
  end

  defp wait_for_scheduler do
    case Process.whereis(ExGoCD.Scheduler) do
      nil ->
        Process.sleep(10)
        wait_for_scheduler()
      pid ->
        if Process.alive?(pid) do
          :ok
        else
          Process.sleep(10)
          wait_for_scheduler()
        end
    end
  end
end
