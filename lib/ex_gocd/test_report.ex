defmodule ExGoCD.TestReport do
  @moduledoc """
  Generates HTML test reports from JUnit XML files uploaded as job artifacts.

  Mirrors GoCD's UnitTestReportGenerator: merges JUnit XML files from testoutput/
  into a single index.html rendered via an EEx template.
  """

  require Logger

  @testoutput_dir "testoutput"
  @report_file "index.html"

  @doc """
  Generates a test report for the given job artifact directory.
  Returns `{:ok, html_path}` on success, or `{:error, reason}`.
  """
  def generate(job_artifact_dir) do
    test_dir = Path.join(job_artifact_dir, @testoutput_dir)

    unless File.dir?(test_dir) do
      {:ok, File.mkdir_p!(test_dir)}
    end

    xml_files = find_junit_xml(test_dir)

    if Enum.empty?(xml_files) do
      {:error, :no_test_files}
    else
      case merge_and_transform(xml_files, test_dir) do
        {:ok, html_path} ->
          Logger.info("Test report generated: #{html_path} (#{length(xml_files)} test files)")
          {:ok, html_path}

        {:error, reason} ->
          Logger.error("Test report generation failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Checks if a test report index.html exists for the given job artifact directory.
  """
  def exists?(job_artifact_dir) do
    test_dir = Path.join(job_artifact_dir, @testoutput_dir)
    File.exists?(Path.join(test_dir, @report_file))
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp find_junit_xml(test_dir) do
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

  defp merge_and_transform(xml_files, output_dir) do
    suites = Enum.map(xml_files, &parse_junit_file/1)

    case suites do
      [] ->
        {:error, :no_valid_test_files}

      all_suites ->
        merged = merge_suites(all_suites)
        html = render_report(merged)
        html_path = Path.join(output_dir, @report_file)

        case File.write(html_path, html) do
          :ok -> {:ok, html_path}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Parse a single JUnit XML file into a map of test suite data
  defp parse_junit_file(file_path) do
    case File.read(file_path) do
      {:ok, xml} ->
        case parse_xml_safe(xml, file_path) do
          {:ok, suite} ->
            suite

          :error ->
            %{
              name: Path.basename(file_path),
              tests: 0,
              failures: 0,
              errors: 0,
              skipped: 0,
              time: 0,
              cases: []
            }
        end

      {:error, _} ->
        %{
          name: Path.basename(file_path),
          tests: 0,
          failures: 0,
          errors: 0,
          skipped: 0,
          time: 0,
          cases: []
        }
    end
  end

  # Parse XML using Erlang's built-in xmerl
  defp parse_xml_safe(xml, file_path) do
    try do
      {root, _rest} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
      {:ok, extract_suite(root, Path.basename(file_path))}
    rescue
      _ -> :error
    catch
      _, _ -> :error
    end
  end

  defp extract_suite(
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
      result: case_result(children),
      message: extract_message(children),
      type: extract_failure_type(children)
    }

    extract_testcases(rest, [tc | acc])
  end

  defp extract_testcases([_other | rest], acc), do: extract_testcases(rest, acc)

  defp case_result(children) do
    has_tag = fn tag ->
      Enum.any?(children, fn
        {:xmlElement, ^tag, ^tag, _, _, _, _, _, _, _, _, _} -> true
        _ -> false
      end)
    end

    cond do
      has_tag.(:failure) -> "failed"
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

  # Render the merged results as HTML
  defp render_report(report) do
    pct = fn n, d ->
      if d > 0, do: Float.round(n * 1.0 / d * 100.0, 1), else: 0.0
    end

    suite_rows =
      Enum.map(report.suites, fn suite ->
        header = """
        <tr class="suite-header"><td colspan="4">#{escape_html(suite.name)} &mdash; #{suite.tests} tests</td></tr>
        """

        cases =
          Enum.map(suite.cases, fn tc ->
            result_class = "result-#{tc.result}"

            """
            <tr>
              <td>#{escape_html(tc.name)}</td>
              <td>#{escape_html(tc.classname)}</td>
              <td class="#{result_class}">#{String.upcase(tc.result)}</td>
              <td>#{Float.round(tc.time, 3)}s</td>
            </tr>
            """
          end)

        header <> Enum.join(cases)
      end)

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Test Report</title>
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f4f8f9; color: #333; padding: 24px; }
      h1 { font-size: 20px; margin-bottom: 16px; color: #1a1a1a; }
      .summary { display: flex; gap: 16px; margin-bottom: 24px; flex-wrap: wrap; }
      .summary-card { background: #fff; border: 1px solid #e0e0e0; border-radius: 8px; padding: 16px 24px; text-align: center; min-width: 100px; }
      .summary-card .count { font-size: 28px; font-weight: 700; }
      .summary-card .label { font-size: 11px; text-transform: uppercase; color: #888; font-weight: 600; letter-spacing: 0.5px; margin-top: 4px; }
      .summary-card.total .count { color: #2d6ca2; }
      .summary-card.passed .count { color: #5cb85c; }
      .summary-card.failed .count { color: #d9534f; }
      .summary-card.errored .count { color: #f0ad4e; }
      .summary-card.skipped .count { color: #999; }
      .summary-card.time .count { font-size: 18px; color: #666; }
      table { width: 100%; border-collapse: collapse; background: #fff; border: 1px solid #e0e0e0; border-radius: 8px; overflow: hidden; }
      th { background: #f8f9fa; padding: 10px 14px; font-size: 10px; text-transform: uppercase; letter-spacing: 0.5px; color: #888; text-align: left; font-weight: 700; }
      td { padding: 9px 14px; font-size: 13px; border-top: 1px solid #f0f0f0; font-family: 'SF Mono', 'Fira Code', monospace; }
      tr:hover td { background: #f8fbff; }
      .result-passed { color: #5cb85c; font-weight: 600; }
      .result-failed { color: #d9534f; font-weight: 600; }
      .result-error { color: #f0ad4e; font-weight: 600; }
      .result-skipped { color: #999; }
      .suite-header td { background: #f0f4f8; font-weight: 700; font-size: 12px; color: #555; text-transform: uppercase; letter-spacing: 0.3px; padding-top: 14px; border-top: 2px solid #e0e0e0; }
      .progress-bar { height: 6px; background: #e9ecef; border-radius: 3px; overflow: hidden; margin-top: 16px; margin-bottom: 24px; }
      .progress-bar .passed-fill { background: #5cb85c; }
      .progress-bar .failed-fill { background: #d9534f; }
      .progress-bar .errored-fill { background: #f0ad4e; }
      .progress-bar .skipped-fill { background: #ccc; }
      .progress-segments { display: flex; height: 100%; }
      .progress-segments div { height: 100%; }
    </style>
    </head>
    <body>
    <h1>Test Report</h1>

    <div class="summary">
      <div class="summary-card total">
        <div class="count">#{report.total_tests}</div>
        <div class="label">Total</div>
      </div>
      <div class="summary-card passed">
        <div class="count">#{report.passed}</div>
        <div class="label">Passed</div>
      </div>
      <div class="summary-card failed">
        <div class="count">#{report.failed}</div>
        <div class="label">Failed</div>
      </div>
      <div class="summary-card errored">
        <div class="count">#{report.errored}</div>
        <div class="label">Errors</div>
      </div>
      <div class="summary-card skipped">
        <div class="count">#{report.skipped}</div>
        <div class="label">Skipped</div>
      </div>
      <div class="summary-card time">
        <div class="count">#{Float.round(report.total_time, 2)}s</div>
        <div class="label">Duration</div>
      </div>
    </div>

    <div class="progress-bar">
      <div class="progress-segments">
        <div class="passed-fill" style="width: #{pct.(report.passed, report.total_tests)}%;"></div>
        <div class="failed-fill" style="width: #{pct.(report.failed, report.total_tests)}%;"></div>
        <div class="errored-fill" style="width: #{pct.(report.errored, report.total_tests)}%;"></div>
        <div class="skipped-fill" style="width: #{pct.(report.skipped, report.total_tests)}%;"></div>
      </div>
    </div>

    <table>
      <thead>
        <tr>
          <th>Test Case</th>
          <th>Class</th>
          <th>Result</th>
          <th>Time</th>
        </tr>
      </thead>
      <tbody>
    #{Enum.join(suite_rows)}
      </tbody>
    </table>
    </body>
    </html>
    """
  end

  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
