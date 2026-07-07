defmodule ExGoCD.TestReport do
  @moduledoc """
  Parses test result XML files (JUnit, NUnit, XUnit) uploaded as test artifacts
  and persists results to the database.

  Mirrors GoCD's UnitTestReportGenerator: merges test XML files from testoutput/
  into a structured report. Unlike GoCD (which writes an index.html file artifact),
  results are stored in DB so they survive artifact cleanup and enable trend queries.

  GoCD reference:
    config/config-api/.../TestArtifactConfig.java — type="test", dest defaults to "testoutput"
    domain/.../UnitTestReportGenerator.java — merges XML, generates XSLT HTML
  """

  require Logger

  import Ecto.Query

  alias ExGoCD.Repo
  alias ExGoCD.TestReport.{TestReport, TestSuite, TestCase}

  @testoutput_dir "testoutput"

  @doc """
  Parses test XML files from the job artifact directory and stores results in the database.
  Returns `{:ok, report}` on success, or `{:error, reason}`.
  Replaces any existing report for the same job instance (re-parse on re-upload).
  """
  @spec parse_and_store(String.t(), integer()) :: {:ok, TestReport.t()} | {:error, atom()}
  def parse_and_store(job_artifact_dir, job_instance_id) do
    test_dir = Path.join(job_artifact_dir, @testoutput_dir)

    xml_files = find_test_xml(test_dir)

    if Enum.empty?(xml_files) do
      {:error, :no_test_files}
    else
      suites = Enum.map(xml_files, &parse_xml_file/1)

      case suites do
        [] ->
          {:error, :no_valid_test_files}

        all_suites ->
          merged = merge_suites(all_suites)
          store_report(merged, job_instance_id)
      end
    end
  end

  @doc """
  Checks if a test report exists in the database for the given job instance.
  """
  @spec exists?(integer()) :: boolean()
  def exists?(job_instance_id) do
    Repo.exists?(
      from(tr in TestReport,
        where: tr.job_instance_id == ^job_instance_id
      )
    )
  end

  @doc """
  Loads a test report with preloaded suites and cases for a job instance.
  Returns nil if no report exists.
  """
  @spec get_by_job_instance(integer()) :: TestReport.t() | nil
  def get_by_job_instance(job_instance_id) do
    Repo.one(
      from(tr in TestReport,
        where: tr.job_instance_id == ^job_instance_id,
        preload: [
          suites: ^from(ts in TestSuite, order_by: ts.name, preload: [:cases])
        ]
      )
    )
  end

  # ── Private: Store ───────────────────────────────────────────────────

  defp store_report(merged, job_instance_id) do
    # Upsert: delete existing report for this job instance, then insert fresh
    Repo.transaction(fn ->
      from(tr in TestReport, where: tr.job_instance_id == ^job_instance_id)
      |> Repo.delete_all()

      {:ok, report} =
        %TestReport{}
        |> TestReport.changeset(%{
          job_instance_id: job_instance_id,
          total_tests: merged.total_tests,
          total_failures: merged.total_failures,
          total_errors: merged.total_errors,
          total_skipped: merged.total_skipped,
          total_time: merged.total_time,
          passed: merged.passed,
          failed: merged.failed,
          errored: merged.errored,
          skipped: merged.skipped
        })
        |> Repo.insert()

      for suite_map <- merged.suites do
        {:ok, suite} =
          %TestSuite{}
          |> TestSuite.changeset(%{
            test_report_id: report.id,
            name: suite_map.name,
            tests: suite_map.tests,
            failures: suite_map.failures,
            errors: suite_map.errors,
            skipped: suite_map.skipped,
            time: suite_map.time
          })
          |> Repo.insert()

        for case_map <- suite_map.cases do
          %TestCase{}
          |> TestCase.changeset(%{
            test_suite_id: suite.id,
            name: case_map.name,
            classname: case_map.classname,
            time: case_map.time,
            result: case_map.result,
            message: case_map.message,
            failure_type: case_map.type
          })
          |> Repo.insert!()
        end
      end

      Logger.info("Test report stored: #{merged.total_tests} tests in #{length(merged.suites)} suites")

      Repo.one!(
        from(tr in TestReport,
          where: tr.id == ^report.id,
          preload: [suites: ^from(ts in TestSuite, order_by: ts.name, preload: [:cases])]
        )
      )
    end)
    |> case do
      {:ok, report} -> {:ok, report}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Private: File discovery ──────────────────────────────────────────

  defp find_test_xml(test_dir) do
    case File.ls(test_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".xml"))
        |> Enum.map(&Path.join(test_dir, &1))
        |> Enum.filter(&File.regular?/1)

      {:error, _} ->
        []
    end
  end

  # ── Private: XML parsing dispatch ────────────────────────────────────

  defp parse_xml_file(file_path) do
    case File.read(file_path) do
      {:ok, xml} ->
        case parse_xml_safe(xml, file_path) do
          {:ok, suites} when is_list(suites) -> suites
          {:ok, suite} -> [suite]
          :error -> []
        end

      {:error, _} ->
        []
    end
  end

  defp parse_xml_safe(xml, file_path) do
    try do
      {root, _rest} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)

      case detect_format(root) do
        :junit -> {:ok, extract_junit_suite(root, Path.basename(file_path))}
        :nunit -> {:ok, extract_nunit_suites(root)}
        :xunit -> {:ok, extract_xunit_suites(root)}
        :unknown -> :error
      end
    rescue
      _ -> :error
    catch
      _, _ -> :error
    end
  end

  # Detect XML format by root element tag
  defp detect_format(
         {:xmlElement, :testsuite, :testsuite, _, _, _, _, _, _, _, _, _}
       ),
       do: :junit

  defp detect_format(
         {:xmlElement, :"test-results", :"test-results", _, _, _, _, _, _, _, _, _}
       ),
       do: :nunit

  defp detect_format(
         {:xmlElement, :assemblies, :assemblies, _, _, _, _, _, _, _, _, _}
       ),
       do: :xunit

  defp detect_format(_), do: :unknown

  # ══════════════════════════════════════════════════════════════════
  # JUnit parser (<testsuite><testcase>)
  # ══════════════════════════════════════════════════════════════════

  defp extract_junit_suite(
         {:xmlElement, :testsuite, :testsuite, _, _, _, _, attrs, children, _, _, _},
         default_name
       ) do
    cases = extract_testcases(children, [])

    %{
      name: get_xml_attr(attrs, :name, String.to_charlist(default_name)) |> List.to_string(),
      tests: get_xml_attr(attrs, :tests, ~c"0") |> List.to_string() |> parse_int(),
      failures: get_xml_attr(attrs, :failures, ~c"0") |> List.to_string() |> parse_int(),
      errors: get_xml_attr(attrs, :errors, ~c"0") |> List.to_string() |> parse_int(),
      skipped: get_xml_attr(attrs, :skipped, ~c"0") |> List.to_string() |> parse_int(),
      time: get_xml_attr(attrs, :time, ~c"0") |> List.to_string() |> parse_float(),
      cases: Enum.reverse(cases)
    }
  end

  defp extract_testcases([], acc), do: acc

  defp extract_testcases(
         [{:xmlElement, :testcase, :testcase, _, _, _, _, attrs, children, _, _, _} | rest],
         acc
       ) do
    tc = %{
      name: get_xml_attr(attrs, :name, ~c"unknown") |> List.to_string(),
      classname: get_xml_attr(attrs, :classname, ~c"") |> List.to_string(),
      time: get_xml_attr(attrs, :time, ~c"0") |> List.to_string() |> parse_float(),
      result: case_result(children, :junit),
      message: extract_message(children),
      type: extract_failure_type(children)
    }

    extract_testcases(rest, [tc | acc])
  end

  defp extract_testcases([_other | rest], acc), do: extract_testcases(rest, acc)

  # ══════════════════════════════════════════════════════════════════
  # NUnit parser (<test-results><test-suite><results><test-case>)
  # GoCD reference: unittests.xsl handles 'test-results' root
  # ══════════════════════════════════════════════════════════════════

  defp extract_nunit_suites(
         {:xmlElement, :"test-results", :"test-results", _, _, _, _, root_attrs, children, _, _, _}
       ) do
    total = get_xml_attr(root_attrs, :total, ~c"0") |> List.to_string() |> parse_int()
    failures = get_xml_attr(root_attrs, :failures, ~c"0") |> List.to_string() |> parse_int()
    errors = get_xml_attr(root_attrs, :errors, ~c"0") |> List.to_string() |> parse_int()
    skipped = get_xml_attr(root_attrs, :skipped, ~c"0") |> List.to_string() |> parse_int()
    time = get_xml_attr(root_attrs, :time, ~c"0") |> List.to_string() |> parse_float()

    suites = extract_nunit_suite_children(children, [])

    # If no child test-suites found, treat the root as a single suite
    if suites == [] do
      cases = extract_nunit_testcases(children, [])

      [
        %{
          name: get_xml_attr(root_attrs, :name, ~c"Test Results") |> List.to_string(),
          tests: total,
          failures: failures,
          errors: errors,
          skipped: skipped,
          time: time,
          cases: cases
        }
      ]
    else
      suites
    end
  end

  defp extract_nunit_suite_children([], acc), do: acc

  defp extract_nunit_suite_children(
         [{:xmlElement, :"test-suite", :"test-suite", _, _, _, _, attrs, children, _, _, _} | rest],
         acc
       ) do
    suite = %{
      name: get_xml_attr(attrs, :name, ~c"unknown") |> List.to_string(),
      tests:
        get_xml_attr(attrs, :total, ~c"0") |> List.to_string() |> parse_int(),
      failures:
        get_xml_attr(attrs, :failures, ~c"0") |> List.to_string() |> parse_int(),
      errors:
        get_xml_attr(attrs, :errors, ~c"0") |> List.to_string() |> parse_int(),
      skipped:
        get_xml_attr(attrs, :skipped, ~c"0") |> List.to_string() |> parse_int(),
      time: get_xml_attr(attrs, :time, ~c"0") |> List.to_string() |> parse_float(),
      cases: extract_nunit_testcases(children, [])
    }

    extract_nunit_suite_children(rest, [suite | acc])
  end

  defp extract_nunit_suite_children([_other | rest], acc),
    do: extract_nunit_suite_children(rest, acc)

  defp extract_nunit_testcases([], acc), do: Enum.reverse(acc)

  defp extract_nunit_testcases(
         [{:xmlElement, :"test-case", :"test-case", _, _, _, _, attrs, tc_children, _, _, _} | rest],
         acc
       ) do
    tc = %{
      name: get_xml_attr(attrs, :name, ~c"unknown") |> List.to_string(),
      classname:
        get_xml_attr(attrs, :description, ~c"") |> List.to_string(),
      time: get_xml_attr(attrs, :time, ~c"0") |> List.to_string() |> parse_float(),
      result: case_result(tc_children, :nunit),
      message: extract_message(tc_children),
      type: extract_failure_type(tc_children)
    }

    extract_nunit_testcases(rest, [tc | acc])
  end

  defp extract_nunit_testcases([_other | rest], acc),
    do: extract_nunit_testcases(rest, acc)

  # ══════════════════════════════════════════════════════════════════
  # XUnit parser (<assemblies><assembly><collection><test>)
  # ══════════════════════════════════════════════════════════════════

  defp extract_xunit_suites(
         {:xmlElement, :assemblies, :assemblies, _, _, _, _, _, children, _, _, _}
       ) do
    suites = extract_xunit_assemblies(children, [])

    if suites == [] do
      cases = extract_xunit_testcases(children, [])

      [
        %{
          name: "Test Results",
          tests: length(cases),
          failures: Enum.count(cases, &(&1.result == "failed")),
          errors: Enum.count(cases, &(&1.result == "error")),
          skipped: Enum.count(cases, &(&1.result == "skipped")),
          time: Enum.sum(Enum.map(cases, & &1.time)),
          cases: cases
        }
      ]
    else
      suites
    end
  end

  defp extract_xunit_assemblies([], acc), do: acc

  defp extract_xunit_assemblies(
         [{:xmlElement, :assembly, :assembly, _, _, _, _, attrs, children, _, _, _} | rest],
         acc
       ) do
    assembly_name =
      get_xml_attr(attrs, :name, ~c"unknown") |> List.to_string()

    sub_suites = extract_xunit_collections(children, assembly_name, [])
    extract_xunit_assemblies(rest, sub_suites ++ acc)
  end

  defp extract_xunit_assemblies([_other | rest], acc),
    do: extract_xunit_assemblies(rest, acc)

  defp extract_xunit_collections([], _assembly_name, acc), do: acc

  defp extract_xunit_collections(
         [{:xmlElement, :collection, :collection, _, _, _, _, attrs, children, _, _, _} | rest],
         assembly_name,
         acc
       ) do
    coll_name =
      get_xml_attr(attrs, :name, ~c"unknown") |> List.to_string()

    cases = extract_xunit_testcases(children, [])

    suite = %{
      name: "#{assembly_name}.#{coll_name}",
      tests: length(cases),
      failures: Enum.count(cases, &(&1.result == "failed")),
      errors: Enum.count(cases, &(&1.result == "error")),
      skipped: Enum.count(cases, &(&1.result == "skipped")),
      time: Enum.sum(Enum.map(cases, & &1.time)),
      cases: cases
    }

    extract_xunit_collections(rest, assembly_name, [suite | acc])
  end

  defp extract_xunit_collections([_other | rest], assembly_name, acc),
    do: extract_xunit_collections(rest, assembly_name, acc)

  defp extract_xunit_testcases([], acc), do: Enum.reverse(acc)

  defp extract_xunit_testcases(
         [{:xmlElement, :test, :test, _, _, _, _, attrs, tc_children, _, _, _} | rest],
         acc
       ) do
    tc = %{
      name: get_xml_attr(attrs, :name, ~c"unknown") |> List.to_string(),
      classname:
        get_xml_attr(attrs, :type, ~c"") |> List.to_string(),
      time: get_xml_attr(attrs, :time, ~c"0") |> List.to_string() |> parse_float(),
      result: case_result(tc_children, :xunit),
      message: extract_message(tc_children),
      type: extract_failure_type(tc_children)
    }

    extract_xunit_testcases(rest, [tc | acc])
  end

  defp extract_xunit_testcases([_other | rest], acc),
    do: extract_xunit_testcases(rest, acc)

  # ══════════════════════════════════════════════════════════════════
  # Shared helpers
  # ══════════════════════════════════════════════════════════════════

  defp case_result(children, format) do
    has_tag = fn tag ->
      Enum.any?(children, fn
        {:xmlElement, ^tag, ^tag, _, _, _, _, _, _, _, _, _} -> true
        _ -> false
      end)
    end

    # NUnit v2 uses success="False" attribute instead of child tags
    nunit_failure? = fn ->
      format == :nunit &&
        Enum.any?(children, fn
          {:xmlAttribute, :success, _, _, _, _, _, _, value, _} ->
            List.to_string(value) in ~w(False false)

          _ ->
            false
        end)
    end

    cond do
      has_tag.(:failure) -> "failed"
      nunit_failure?.() -> "failed"
      has_tag.(:error) -> "error"
      has_tag.(:skipped) -> "skipped"
      true -> "passed"
    end
  end

  defp extract_message(children) do
    find_child_text(children, [:failure, :error])
  end

  defp extract_failure_type(children) do
    child =
      Enum.find(children, fn
        {:xmlElement, tag, _, _, _, _, _, _, _, _, _, _} when tag in [:failure, :error] -> true
        _ -> false
      end)

    case child do
      {:xmlElement, _, _, _, _, _, _, _, attrs, _, _, _} ->
        get_xml_attr(attrs, :type, nil) |> to_string_or_nil()

      _ ->
        nil
    end
  end

  defp get_xml_attr(attrs, name, default) do
    case List.keyfind(attrs, name, 1) do
      {:xmlAttribute, ^name, _, _, _, _, _, _, value, _} -> value
      _ -> default
    end
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(charlist) when is_list(charlist), do: List.to_string(charlist)

  defp find_child_text(children, tags) do
    child =
      Enum.find(children, fn
        {:xmlElement, tag, _, _, _, _, _, _, _} -> Enum.member?(tags, tag)
        _ -> false
      end)

    case child do
      {:xmlElement, _, _, _, _, _, _, _, sub_children, _, _, _} ->
        text = extract_text(sub_children)
        if text == "", do: nil, else: text

      _ ->
        nil
    end
  end

  defp extract_text(children) do
    children
    |> Enum.filter(&match?({:xmlText, _, _, _, _, _, _}, &1))
    |> Enum.map_join(fn {:xmlText, _, _, _, _, text, _} -> List.to_string(text) end)
    |> String.trim()
  end

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  # Merge multiple test suites into a single summary
  defp merge_suites(suites) do
    all_cases = Enum.flat_map(suites, & &1.cases)

    %{
      suites: suites,
      total_tests: Enum.sum(Enum.map(suites, & &1.tests)),
      total_failures: Enum.sum(Enum.map(suites, & &1.failures)),
      total_errors: Enum.sum(Enum.map(suites, & &1.errors)),
      total_skipped: Enum.sum(Enum.map(suites, & &1.skipped)),
      total_time: Enum.sum(Enum.map(suites, & &1.time)) * 1.0,
      passed: Enum.count(all_cases, &(&1.result == "passed")),
      failed: Enum.count(all_cases, &(&1.result == "failed")),
      errored: Enum.count(all_cases, &(&1.result == "error")),
      skipped: Enum.count(all_cases, &(&1.result == "skipped"))
    }
  end
end
