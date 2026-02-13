defmodule Mix.Tasks.Convert.Gocd.Css do
  use Mix.Task

  @shortdoc "Convert GoCD SCSS to CSS files in assets/css/gocd"

  @moduledoc """
  mix convert.gocd.css [INPUT_DIR] [OUTPUT_DIR]

  Runs the Node-based SCSS → CSS converter.

  If `tools/converter/node_modules` is missing, the task will run `npm ci` in `tools/converter`.
  """

  def run(args) do
    Mix.Task.run("app.start", [])

    root = File.cwd!()
    input = args |> Enum.at(0, "tools/converter/fixtures/source") |> Path.expand(root)
    output = args |> Enum.at(1, "assets/css/gocd") |> Path.expand(root)

    unless File.dir?(input) do
      Mix.raise("Input directory does not exist: #{input}")
    end

    # ensure output dir
    File.mkdir_p!(output)

    converter_dir = Path.join(File.cwd!(), "tools/converter")
    node_modules_dir = Path.join(converter_dir, "node_modules")

    if not File.dir?(node_modules_dir) do
      Mix.shell().info("Installing Node dependencies in #{converter_dir} (npm ci)...")
      {out, 0} = System.cmd("npm", ["ci"], cd: converter_dir, stderr_to_stdout: true)
      Mix.shell().info(out)
    end

    Mix.shell().info("Running converter...")
    {out, status} = System.cmd("node", ["css-convert.js", input, output], cd: converter_dir, stderr_to_stdout: true)

    Mix.shell().info(out)

    if status != 0 do
      Mix.raise("css conversion failed (exit #{status})")
    end

    Mix.shell().info("CSS conversion finished — output directory: #{output}")
  end
end
