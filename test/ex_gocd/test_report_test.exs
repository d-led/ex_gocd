defmodule ExGoCD.TestReportTest do
  use ExGoCD.DataCase, async: true

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

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "test_report_#{System.unique_integer()}")
    test_dir = Path.join(tmp_dir, "testoutput")
    File.mkdir_p!(test_dir)
    File.write!(Path.join(test_dir, "results.xml"), @junit_xml)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir, test_dir: test_dir}
  end

  describe "generate/1" do
    test "generates index.html from JUnit XML", %{tmp_dir: tmp_dir} do
      assert {:ok, html_path} = TestReport.generate(tmp_dir)
      assert String.ends_with?(html_path, "index.html")

      html = File.read!(html_path)
      assert html =~ "Test Report"
      assert html =~ "com.example.MyTest"
      assert html =~ "test_passes"
      assert html =~ "test_fails"
      assert html =~ "test_skipped"
      assert html =~ "3" # total tests
      assert html =~ "FAILED"
      assert html =~ "PASSED"
      assert html =~ "SKIPPED"
    end

    test "returns error when no JUnit XML files", %{tmp_dir: tmp_dir} do
      # Remove the XML file
      File.rm_rf!(Path.join(tmp_dir, "testoutput"))

      assert {:error, :no_test_files} = TestReport.generate(tmp_dir)
    end

    test "handles empty testoutput directory", %{tmp_dir: tmp_dir} do
      File.rm_rf!(Path.join(tmp_dir, "testoutput", "results.xml"))
      File.write!(Path.join(tmp_dir, "testoutput", "empty.xml"), "")

      # xmerl will probably crash on empty XML, but should not crash the whole thing
      {:ok, _} = TestReport.generate(tmp_dir)
    end
  end

  describe "exists?/1" do
    test "returns true when index.html exists", %{tmp_dir: tmp_dir} do
      TestReport.generate(tmp_dir)
      assert TestReport.exists?(tmp_dir)
    end

    test "returns false when no report generated", %{tmp_dir: tmp_dir} do
      refute TestReport.exists?(tmp_dir)
    end
  end
end
