defmodule ExGoCD.AgentJobRunsTest do
  @moduledoc """
  Tests for job execution flow: create_run when a build is sent,
  report_status when the agent reports progress/completion.
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Agents
  alias ExGoCD.AgentJobRuns
  alias ExGoCD.AgentJobRuns.AgentJobRun

  @agent_uuid "550e8400-e29b-41d4-a716-446655440000"

  setup do
    {:ok, _} =
      Agents.register_agent(%{
        uuid: @agent_uuid,
        hostname: "build-agent-1",
        ipaddress: "192.168.1.1"
      })

    %{}
  end

  describe "create_run/5" do
    test "creates a run when a build is sent to an agent" do
      assert {:ok, %AgentJobRun{} = run} =
               AgentJobRuns.create_run(
                 @agent_uuid,
                 "test-job-123",
                 "test-pipeline",
                 "test-stage",
                 "test-job"
               )

      assert run.agent_uuid == @agent_uuid
      assert run.build_id == "test-job-123"
      assert run.pipeline_name == "test-pipeline"
      assert run.stage_name == "test-stage"
      assert run.job_name == "test-job"
      assert run.state == "Assigned"
    end

    test "returns error when agent not found" do
      assert {:error, :agent_not_found} =
               AgentJobRuns.create_run(
                 "00000000-0000-0000-0000-000000000000",
                 "test-job-123",
                 "p",
                 "s",
                 "j"
               )
    end
  end

  describe "report_status/4" do
    test "updates run when agent reports Building then Completed with result" do
      {:ok, _} =
        AgentJobRuns.create_run(@agent_uuid, "build-1", "pipeline", "stage", "job")

      {:ok, _} = AgentJobRuns.report_status(@agent_uuid, "build-1", "Building", nil)
      run = get_run(@agent_uuid, "build-1")
      assert run.state == "Building"
      assert run.result == nil

      {:ok, _} = AgentJobRuns.report_status(@agent_uuid, "build-1", "Completing", nil)
      run = get_run(@agent_uuid, "build-1")
      assert run.state == "Completing"

      {:ok, _} = AgentJobRuns.report_status(@agent_uuid, "build-1", "Completed", "Passed")
      run = get_run(@agent_uuid, "build-1")
      assert run.state == "Completed"
      assert run.result == "Passed"
    end

    test "stores Failed result when agent reports failure" do
      {:ok, _} =
        AgentJobRuns.create_run(@agent_uuid, "build-2", "p", "s", "j")

      {:ok, _} = AgentJobRuns.report_status(@agent_uuid, "build-2", "Building", nil)
      {:ok, _} = AgentJobRuns.report_status(@agent_uuid, "build-2", "Completed", "Failed")

      run = get_run(@agent_uuid, "build-2")
      assert run.state == "Completed"
      assert run.result == "Failed"
    end

    test "stores Cancelled result when agent reports cancelled build" do
      {:ok, _} = AgentJobRuns.create_run(@agent_uuid, "build-3", "p", "s", "j")
      {:ok, _} = AgentJobRuns.report_status(@agent_uuid, "build-3", "Building", nil)
      {:ok, _} = AgentJobRuns.report_status(@agent_uuid, "build-3", "Completed", "Cancelled")

      run = get_run(@agent_uuid, "build-3")
      assert run.state == "Completed"
      assert run.result == "Cancelled"
    end

    test "returns {:error, :run_not_found} when no run exists for build_id" do
      assert {:error, :run_not_found} =
               AgentJobRuns.report_status(@agent_uuid, "nonexistent-build", "Building", nil)
    end
  end

  describe "handle_agent_report/2" do
    test "updates run and agent runtime state from report payload" do
      {:ok, _} = AgentJobRuns.create_run(@agent_uuid, "build-hr", "p", "s", "j")

      payload = %{
        "buildId" => "build-hr",
        "jobState" => "Completed",
        "result" => "Passed",
        "agentRuntimeInfo" => %{"runtimeStatus" => "Idle"}
      }

      assert :ok = AgentJobRuns.handle_agent_report(@agent_uuid, payload)

      run = get_run(@agent_uuid, "build-hr")
      assert run.state == "Completed"
      assert run.result == "Passed"
      agent = Agents.get_agent_by_uuid(@agent_uuid)
      assert agent.state == "Idle"
    end

    test "no-op when buildId or jobState missing" do
      assert :ok = AgentJobRuns.handle_agent_report(@agent_uuid, %{"agentRuntimeInfo" => %{"runtimeStatus" => "Idle"}})
    end
  end

  describe "append_console/2" do
    test "appends chunk to run's console_log" do
      {:ok, run} =
        AgentJobRuns.create_run(@agent_uuid, "build-console-1", "p", "s", "j")

      assert run.console_log == "" || run.console_log == nil

      assert {:ok, run2} = AgentJobRuns.append_console("build-console-1", "line one\n")
      assert run2.console_log == "line one\n"

      assert {:ok, run3} = AgentJobRuns.append_console("build-console-1", "line two\n")
      assert run3.console_log == "line one\nline two\n"
    end

    test "returns {:error, :run_not_found} when build_id does not exist" do
      assert {:error, :run_not_found} =
               AgentJobRuns.append_console("nonexistent-build", "text")
    end
  end

  describe "list_runs_for_agent/1" do
    test "returns runs for agent newest first" do
      {:ok, _} = AgentJobRuns.create_run(@agent_uuid, "build-a", "p", "s", "j")
      {:ok, _} = AgentJobRuns.create_run(@agent_uuid, "build-b", "p", "s", "j")

      runs = AgentJobRuns.list_runs_for_agent(@agent_uuid)
      assert length(runs) == 2
      [first, second] = runs
      assert first.build_id in ["build-a", "build-b"]
      assert second.build_id in ["build-a", "build-b"]
      assert first.inserted_at >= second.inserted_at
    end

    test "returns empty list when agent has no runs" do
      assert AgentJobRuns.list_runs_for_agent(@agent_uuid) == []
    end
  end

  defp get_run(agent_uuid, build_id) do
    ExGoCD.Repo.get_by!(AgentJobRun, agent_uuid: agent_uuid, build_id: build_id)
  end
end
