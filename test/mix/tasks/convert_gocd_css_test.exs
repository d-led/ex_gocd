defmodule Mix.Tasks.Convert.Gocd.CssTest do
  use ExUnit.Case, async: false

  # Aligned with GoCD WebpackAssetsServiceTest: getCSSAssetPathsFor("single_page_apps/agents", "single_page_apps/new_dashboard").
  # We output dashboard.css (from new_dashboard.scss) and agents.css for app imports (see docs/css_conversion_plan.md).
  @gocd_expected_css_basenames ["agents.css", "dashboard.css"]

  @output_dir "tmp/test_assets"
  @input_dir "tools/converter/fixtures/source"
  @converter_dir Path.join(File.cwd!(), "tools/converter")

  setup do
    if File.dir?(@output_dir), do: File.rm_rf!(@output_dir)
    File.mkdir_p!(@output_dir)
    :ok
  end

  defp ensure_node_deps do
    unless File.dir?(Path.join(@converter_dir, "node_modules")) do
      {_out, 0} = System.cmd("npm", ["ci"], cd: @converter_dir, stderr_to_stdout: true)
    end
  end

  describe "entry-point mode (GoCD-aligned)" do
    test "produces exactly the CSS files we use: dashboard.css and agents.css" do
      ensure_node_deps()
      input = Path.expand(@input_dir, File.cwd!())
      output = Path.expand(@output_dir, File.cwd!())

      Mix.Tasks.Convert.Gocd.Css.run([input, output])

      for basename <- @gocd_expected_css_basenames do
        path = Path.join(@output_dir, basename)
        assert File.exists?(path), "expected GoCD output file #{basename} to exist"
      end

      # No extra CSS files beyond what we generate (idempotent set)
      out_files = @output_dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".css"))

      assert Enum.sort(out_files) == Enum.sort(@gocd_expected_css_basenames),
             "output should contain only GoCD entry-point CSS files, got: #{inspect(out_files)}"
    end

    test "compiled CSS contains expanded variables and header comment" do
      ensure_node_deps()
      Mix.Tasks.Convert.Gocd.Css.run([@input_dir, @output_dir])

      content = File.read!(Path.join(@output_dir, "dashboard.css"))
      assert content =~ "Converted from", "contains header comment"
      assert content =~ "background: #000728", "variable $site-header expanded"
      assert content =~ ~r/@media \(min-width: 768px\)/, "media query variable expanded"
    end

    test "agents.css is produced and contains compiled content" do
      ensure_node_deps()
      Mix.Tasks.Convert.Gocd.Css.run([@input_dir, @output_dir])

      content = File.read!(Path.join(@output_dir, "agents.css"))
      assert content =~ "Converted from"
      assert content =~ "#000728", "variable expanded in agents page"
    end
  end

  describe "idempotency" do
    test "second run leaves same output set; known outputs are replaced not accumulated" do
      ensure_node_deps()
      input = Path.expand(@input_dir, File.cwd!())
      output = Path.expand(@output_dir, File.cwd!())

      Mix.Tasks.Convert.Gocd.Css.run([input, output])
      first_run_files = File.ls!(@output_dir) |> Enum.sort()

      Mix.Tasks.Convert.Gocd.Css.run([input, output])
      second_run_files = File.ls!(@output_dir) |> Enum.sort()

      assert second_run_files == first_run_files,
             "second run must produce the same set of files (idempotent)"

      assert first_run_files == Enum.sort(@gocd_expected_css_basenames)
    end
  end

  describe "failure when entry is missing" do
    test "converter exits non-zero when an entry point file is missing" do
      ensure_node_deps()
      input = Path.expand(@input_dir, File.cwd!())
      output = Path.expand(@output_dir, File.cwd!())
      # Pass a non-existent entry along with a valid one
      args = [
        "css-convert.js",
        input,
        output,
        "single_page_apps/new_dashboard.scss",
        "single_page_apps/nonexistent.scss"
      ]

      {_out, status} = System.cmd("node", args, cd: @converter_dir, stderr_to_stdout: true)
      assert status != 0, "converter should fail when an entry point is missing"
    end
  end
end
