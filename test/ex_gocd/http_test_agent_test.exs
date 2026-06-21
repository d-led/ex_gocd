# Copyright 2026 ex_gocd
# Integration tests for ExGoCD.HTTPTestAgent.

defmodule ExGoCD.HTTPTestAgentTest do
  use ExGoCD.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents
  alias ExGoCD.Scheduler
  alias ExGoCD.TestAgent.UUID
  alias ExGoCD.TestAgentSupervisor

  setup do
    wait_for_scheduler()
    TestAgentSupervisor.stop_all_agents()

    # 1. Enable server dynamically on port 4002
    orig_config = Application.get_env(:ex_gocd, ExGoCDWeb.Endpoint)
    new_config =
      orig_config
      |> Keyword.put(:server, true)
      |> Keyword.put(:http, [ip: {127, 0, 0, 1}, port: 4002])
    Application.put_env(:ex_gocd, ExGoCDWeb.Endpoint, new_config)

    # Restart endpoint
    _ = Supervisor.terminate_child(ExGoCD.Supervisor, ExGoCDWeb.Endpoint)
    _ = Supervisor.restart_child(ExGoCD.Supervisor, ExGoCDWeb.Endpoint)

    # 2. Start the HTTP test agent pointing to port 4002
    uuid = UUID.uuid4()
    {:ok, agent_pid} = TestAgentSupervisor.start_http_agent(
      uuid: uuid,
      port: 4002,
      host: "127.0.0.1",
      ping_interval: 1000
    )

    on_exit(fn ->
      TestAgentSupervisor.stop_all_agents()
      Application.put_env(:ex_gocd, ExGoCDWeb.Endpoint, orig_config)
      _ = Supervisor.terminate_child(ExGoCD.Supervisor, ExGoCDWeb.Endpoint)
      _ = Supervisor.restart_child(ExGoCD.Supervisor, ExGoCDWeb.Endpoint)
    end)

    %{uuid: uuid, pid: agent_pid}
  end

  test "agent registers via HTTP, connects via WebSocket, and executes jobs", %{uuid: uuid} do
    # 1. Verify agent registers in DB
    assert_receive_or_retry(20, fn ->
      agent = Agents.get_agent_by_uuid(uuid)
      agent != nil and agent.state == "Idle" and agent.disabled == false
    end)

    # 2. Schedule a job
    {:ok, _job_id} = Scheduler.schedule_job(%{
      pipeline: "http-pipeline",
      stage: "http-stage",
      job: "http-job",
      environments: []
    })

    # Trigger job assignment
    Scheduler.try_assign_work(uuid)

    # 3. Wait for the agent to start execution
    assert_receive_or_retry(20, fn ->
      updated_agent = Agents.get_agent_by_uuid(uuid)
      updated_agent.state == "Building"
    end)

    # Check that a run was created
    runs = AgentJobRuns.list_runs_for_agent(uuid)
    assert length(runs) == 1
    run = List.first(runs)
    assert run.pipeline_name == "http-pipeline"

    # 4. Wait for completion
    assert_receive_or_retry(40, fn ->
      updated_agent = Agents.get_agent_by_uuid(uuid)
      latest_run = List.first(AgentJobRuns.list_runs_for_agent(uuid))
      updated_agent.state == "Idle" and latest_run.state == "Completed" and latest_run.result == "Passed"
    end)

    # 5. Verify console logs uploaded by HTTPTestAgent
    latest_run = List.first(AgentJobRuns.list_runs_for_agent(uuid))
    assert latest_run.console_log =~ "Preparing build workspace..."
    assert latest_run.console_log =~ "Executing build task: mix test"
    assert latest_run.console_log =~ "Build completed successfully."
  end

  # Helpers
  defp assert_receive_or_retry(retries, func) do
    if func.() do
      true
    else
      if retries > 0 do
        Process.sleep(100)
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
