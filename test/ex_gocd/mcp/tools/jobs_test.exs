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

    job_instance =
      insert_job_instance(stage.id, "compile", DateTime.utc_now(), DateTime.utc_now())

    Repo.insert!(%Agent{
      uuid: "agent-1",
      hostname: "build-1",
      ipaddress: "10.0.0.1",
      state: "Idle"
    })

    {:ok, job_instance: job_instance}
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

  describe "gocd_test_report" do
    test "a job that published no report says so, rather than meaning all tests passed" do
      assert {:error, message} = Tools.call("gocd_test_report", job_args(), @ctx)
      assert message =~ "published none"
    end

    test "the failed cases are named, with the first line of each message", %{
      job_instance: job_instance
    } do
      store_report(job_instance.id)

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_test_report", job_args(), @ctx)

      assert structured["totals"] == %{
               "total" => 2,
               "passed" => 1,
               "failed" => 1,
               "errored" => 0,
               "skipped" => 0,
               "time_seconds" => 0.3
             }

      assert [%{"test" => "fails", "result" => "failed", "message" => message}] =
               structured["cases"]

      assert message == "Expected 42 but got 0"
      assert text =~ "1 failed"
      refute text =~ "passes"
    end

    test "all the cases are listed when the caller asks for them", %{job_instance: job_instance} do
      store_report(job_instance.id)

      assert {:ok, %{structured: structured}} =
               Tools.call("gocd_test_report", Map.put(job_args(), "failed_only", false), @ctx)

      assert Enum.map(structured["cases"], & &1["test"]) == ["passes", "fails"]
    end
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

  # The report is stored the way a job stores it: a JUnit file under `testoutput/`
  # in the job's artifact directory, parsed by the code that parses it in
  # production.
  defp store_report(job_instance_id) do
    dir = Path.join(System.tmp_dir!(), "mcp-report-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "testoutput"))
    File.write!(Path.join([dir, "testoutput", "report.xml"]), junit_xml())
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, _report} = ExGoCD.TestReport.parse_and_store(dir, job_instance_id)
  end

  defp junit_xml do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <testsuite name="checks" tests="2" failures="1" errors="0" skipped="0" time="0.30">
      <testcase name="passes" classname="checks" time="0.10"/>
      <testcase name="fails" classname="checks" time="0.20">
        <failure message="expected: 42, got: 0" type="AssertionError">Expected 42 but got 0
    at checks.fails(checks_test.exs:9)</failure>
      </testcase>
    </testsuite>
    """
  end
end
