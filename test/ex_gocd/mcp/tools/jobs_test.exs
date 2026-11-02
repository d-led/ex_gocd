defmodule ExGoCD.Mcp.Tools.JobsTest do
  @moduledoc """
  A job is what the pipeline asked for; a job run is what an agent did. The
  console lives on the second, so these tests make both.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents.Agent
  alias ExGoCD.Mcp.Tools.Jobs, as: Tools
  alias ExGoCD.Repo

  @ctx %{
    user: %ExGoCD.Accounts.User{username: "admin", roles: ["admin"], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  setup do
    insert_pipeline("console-app")
    instance = insert_pipeline_instance_by_name("console-app", 1, DateTime.utc_now())
    stage = insert_stage_instance(instance.id, "build", state: "Completed", result: "Failed")
    insert_job_instance(stage.id, "compile", DateTime.utc_now(), DateTime.utc_now())

    agent =
      Repo.insert!(%Agent{
        uuid: "agent-1",
        hostname: "build-1",
        ipaddress: "10.0.0.1",
        state: "Idle"
      })

    :ok
  end

  test "a job with no run yet says so instead of showing an empty console" do
    assert {:error, message} = Tools.call("gocd_job_console", job_args(), @ctx)
    assert message =~ "no console to read"
  end

  test "the console is the last lines of what the agent wrote" do
    {_run, _agent} = run_with_console(["starting", "compiling", "error: boom"])

    assert {:ok, %{text: text, structured: structured}} =
             Tools.call("gocd_job_console", Map.put(job_args(), "lines", 2), @ctx)

    assert structured["lines"] == 3
    assert text =~ "error: boom"
    assert text =~ "1 earlier line(s) not shown"
    refute text =~ "starting"
  end

  test "one job is described with its run's build id" do
    {run, _agent} = run_with_console(["compiling"])

    assert {:ok, %{structured: structured}} = Tools.call("gocd_job", job_args(), @ctx)

    assert structured["job"]["name"] == "compile"
    assert structured["run"]["build_id"] == run.build_id
    assert structured["run"]["console_lines"] == 1
  end

  test "the job's history lists its instances, newest run first" do
    assert {:ok, %{structured: structured}} =
             Tools.call(
               "gocd_job_history",
               %{"pipeline" => "console-app", "stage" => "build", "job" => "compile"},
               @ctx
             )

    assert [%{"name" => "compile", "state" => "Completed"}] = structured["instances"]
  end

  defp job_args do
    %{
      "pipeline" => "console-app",
      "counter" => 1,
      "stage" => "build",
      "stage_counter" => 1,
      "job" => "compile"
    }
  end

  defp run_with_console(lines) do
    agent = Repo.get_by!(Agent, uuid: "agent-1")

    {:ok, run} =
      AgentJobRuns.create_run(agent.uuid, "build-1", "console-app", "build", "compile",
        pipeline_counter: 1,
        stage_counter: 1
      )

    Enum.each(lines, &AgentJobRuns.append_console(run.build_id, &1 <> "\n"))

    {run, agent}
  end
end
