defmodule ExGoCD.TestReportTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Repo
  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance, Stage, StageInstance, Job, JobInstance}
  alias ExGoCD.TestReport

  @junit_xml ~S"""
  <?xml version="1.0" encoding="UTF-8"?>
  <testsuite name="com.example.MyTest" tests="3" failures="1" errors="0" skipped="1" time="0.42">
    <testcase name="test_passes" classname="com.example.MyTest" time="0.12"/>
    <testcase name="test_fails" classname="com.example.MyTest" time="0.15">
      <failure message="expected: 42, got: 0" type="AssertionError">
        Expected 42 but got 0
      </failure>
    </testcase>
    <testcase name="test_skipped" classname="com.example.MyTest" time="0.01">
      <skipped/>
    </testcase>
  </testsuite>
  """

  @nunit_xml ~S"""
  <?xml version="1.0" encoding="UTF-8"?>
  <test-results name="NUnit Tests" total="2" failures="1" errors="0" skipped="0" time="1.23">
    <test-suite name="MyNamespace.TestSuite" total="2" failures="1" errors="0" skipped="0" time="1.23">
      <results>
        <test-case name="test_one" description="MyNamespace.TestSuite.test_one" time="0.5" success="True"/>
        <test-case name="test_two" description="MyNamespace.TestSuite.test_two" time="0.73" success="False">
          <failure>
            <message>Expected true but was false</message>
            <stack-trace>at MyNamespace.TestSuite.test_two()</stack-trace>
          </failure>
        </test-case>
      </results>
    </test-suite>
  </test-results>
  """

  @xunit_xml ~S"""
  <?xml version="1.0" encoding="UTF-8"?>
  <assemblies>
    <assembly name="MyTests.dll" total="2" passed="1" failed="1" skipped="0" time="1.5">
      <collection name="TestCollection" total="2" passed="1" failed="1" skipped="0" time="1.5">
        <test name="MyTests.TestOne" type="MyTests.TestClass" time="0.6"/>
        <test name="MyTests.TestTwo" type="MyTests.TestClass" time="0.9">
          <failure exception-type="Xunit.Sdk.EqualException">
            <message>Assert.Equal() Failure: Values differ</message>
          </failure>
        </test>
      </collection>
    </assembly>
  </assemblies>
  """

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "test_report_#{System.unique_integer()}")
    test_dir = Path.join(tmp_dir, "testoutput")
    File.mkdir_p!(test_dir)

    uniq = System.unique_integer()

    {:ok, pipeline} =
      %Pipeline{name: "test-pipeline-#{uniq}"}
      |> Pipeline.changeset(%{})
      |> Repo.insert()

    {:ok, stage} =
      %Stage{name: "test-stage", pipeline_id: pipeline.id}
      |> Stage.changeset(%{})
      |> Repo.insert()

    {:ok, job} =
      %Job{name: "test-job", stage_id: stage.id}
      |> Job.changeset(%{stage_id: stage.id})
      |> Repo.insert()

    {:ok, pi} =
      %PipelineInstance{counter: 1, pipeline_id: pipeline.id}
      |> PipelineInstance.changeset(%{
        label: "1",
        natural_order: 1.0,
        build_cause: %{"triggerMessage" => "test"}
      })
      |> Repo.insert()

    now = DateTime.utc_now()

    {:ok, si} =
      %StageInstance{
        name: "test-stage",
        counter: 1,
        pipeline_instance_id: pi.id,
        state: "Passed",
        result: "Passed"
      }
      |> StageInstance.changeset(%{
        order_id: 1,
        approval_type: "success",
        created_time: now,
        completed_at: now,
        latest_run: false
      })
      |> Repo.insert()

    {:ok, job_instance} =
      %JobInstance{
        name: "test-job",
        state: "Completed",
        result: "Passed",
        job_id: job.id,
        stage_instance_id: si.id,
        scheduled_at: DateTime.utc_now()
      }
      |> JobInstance.changeset(%{})
      |> Repo.insert()

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir, test_dir: test_dir, job_instance_id: job_instance.id}
  end

  describe "parse_and_store/2 with JUnit" do
    test "parses JUnit XML and stores in DB", ctx do
      File.write!(Path.join(ctx.test_dir, "results.xml"), @junit_xml)

      assert {:ok, report} = TestReport.parse_and_store(ctx.tmp_dir, ctx.job_instance_id)
      assert report.total_tests == 3
      assert report.total_failures == 1
      assert report.total_errors == 0
      assert report.total_skipped == 1
      assert report.passed == 1
      assert report.failed == 1
      assert report.skipped == 1

      report = TestReport.get_by_job_instance(ctx.job_instance_id)
      assert length(report.suites) == 1
      suite = hd(report.suites)
      assert suite.name == "com.example.MyTest"
      assert length(suite.cases) == 3

      cases = suite.cases
      assert Enum.find(cases, &(&1.name == "test_passes" && &1.result == "passed"))
      assert Enum.find(cases, &(&1.name == "test_fails" && &1.result == "failed"))
      assert Enum.find(cases, &(&1.name == "test_skipped" && &1.result == "skipped"))
    end
  end

  describe "parse_and_store/2 with NUnit" do
    test "parses NUnit XML and stores in DB", ctx do
      File.write!(Path.join(ctx.test_dir, "nunit_results.xml"), @nunit_xml)

      assert {:ok, report} = TestReport.parse_and_store(ctx.tmp_dir, ctx.job_instance_id)
      assert report.total_tests == 2
      assert report.total_failures == 1
      assert report.passed == 1
      assert report.failed == 1

      report = TestReport.get_by_job_instance(ctx.job_instance_id)
      suite = hd(report.suites)
      assert suite.name =~ "TestSuite"
      assert length(suite.cases) == 2

      assert Enum.find(suite.cases, &(&1.name == "test_one" && &1.result == "passed"))
      assert Enum.find(suite.cases, &(&1.name == "test_two" && &1.result == "failed"))
    end
  end

  describe "parse_and_store/2 with XUnit" do
    test "parses XUnit XML and stores in DB", ctx do
      File.write!(Path.join(ctx.test_dir, "xunit_results.xml"), @xunit_xml)

      assert {:ok, report} = TestReport.parse_and_store(ctx.tmp_dir, ctx.job_instance_id)
      assert report.total_tests == 2
      assert report.total_failures == 1
      assert report.passed == 1
      assert report.failed == 1

      report = TestReport.get_by_job_instance(ctx.job_instance_id)
      suite = hd(report.suites)
      assert suite.name =~ "MyTests.dll.TestCollection"
      assert length(suite.cases) == 2

      assert Enum.find(suite.cases, &(&1.name == "MyTests.TestOne" && &1.result == "passed"))
      assert Enum.find(suite.cases, &(&1.name == "MyTests.TestTwo" && &1.result == "failed"))
    end
  end

  describe "parse_and_store/2 error handling" do
    test "returns error when no XML files", ctx do
      File.rm_rf!(Path.join(ctx.tmp_dir, "testoutput"))
      File.mkdir_p!(Path.join(ctx.tmp_dir, "testoutput"))

      assert {:error, :no_test_files} =
               TestReport.parse_and_store(ctx.tmp_dir, ctx.job_instance_id)
    end

    test "handles empty XML file gracefully", ctx do
      File.write!(Path.join(ctx.test_dir, "empty.xml"), "")

      assert {:error, :no_valid_test_files} =
               TestReport.parse_and_store(ctx.tmp_dir, ctx.job_instance_id)
    end

    test "upserts: re-parsing replaces existing report", ctx do
      File.write!(Path.join(ctx.test_dir, "results.xml"), @junit_xml)
      assert {:ok, _} = TestReport.parse_and_store(ctx.tmp_dir, ctx.job_instance_id)

      assert {:ok, report2} = TestReport.parse_and_store(ctx.tmp_dir, ctx.job_instance_id)
      assert report2.total_tests == 3

      import Ecto.Query
      alias ExGoCD.TestReport.TestReport

      count =
        Repo.aggregate(
          from(tr in TestReport, where: tr.job_instance_id == ^ctx.job_instance_id),
          :count
        )

      assert count == 1
    end
  end

  describe "exists?/1" do
    test "returns true when report stored in DB", ctx do
      File.write!(Path.join(ctx.test_dir, "results.xml"), @junit_xml)
      TestReport.parse_and_store(ctx.tmp_dir, ctx.job_instance_id)
      assert TestReport.exists?(ctx.job_instance_id)
    end

    test "returns false when no report stored", ctx do
      refute TestReport.exists?(ctx.job_instance_id)
    end
  end
end
