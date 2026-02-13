defmodule Mix.Tasks.Convert.Gocd.CssTest do
  use ExUnit.Case, async: false

  @output_dir "tmp/test_assets"
  @input_dir "tools/converter/fixtures/source"

  setup do
    # clean output dir
    if File.dir?(@output_dir), do: File.rm_rf!(@output_dir)
    File.mkdir_p!(@output_dir)
    :ok
  end

  test "runs converter and produces CSS with resolved variables" do
    # Ensure node deps are installed for the converter
    converter_dir = Path.join(File.cwd!(), "tools/converter")
    unless File.dir?(Path.join(converter_dir, "node_modules")) do
      {out, 0} = System.cmd("npm", ["ci"], cd: converter_dir, stderr_to_stdout: true)
      IO.puts(out)
    end

    Mix.Tasks.Convert.Gocd.Css.run([@input_dir, @output_dir])

    out_file = Path.join(@output_dir, "new_dashboard.css")
    assert File.exists?(out_file), "expected output file exists"

    content = File.read!(out_file)
    assert String.contains?(content, "Converted from"), "contains header comment"
    assert String.contains?(content, "background: #000728"), "variable expanded"
    assert String.contains?(content, "@media (min-width: 768px)"), "media query expanded"
  end
end
