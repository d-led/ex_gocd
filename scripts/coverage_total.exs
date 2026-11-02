# Prints the whole-project line coverage from the coverdata `mix cover` exports.
#
#   PGHOST=127.0.0.1 PGPORT=5544 mix cover      # writes cover/default.coverdata
#   elixir scripts/coverage_total.exs
#
# Mix's own summary is a pass/fail against the floor in mix.exs; this is the
# number a person quotes, so the docs can cite a figure that was measured.

defmodule CoverageTotal do
  @coverdata "cover/default.coverdata"

  def run do
    :cover.start()

    case :cover.import(String.to_charlist(@coverdata)) do
      :ok -> report()
      {:error, reason} -> abort("#{@coverdata} could not be read: #{inspect(reason)}")
    end
  end

  defp report do
    # Imported modules are not cover-compiled, so they are listed separately.
    # Dependencies are compiled into the same export; only our own code counts,
    # and the scaffolding under test/support measures the tests rather than the
    # product.
    counts =
      :cover.imported_modules()
      |> Enum.filter(&own_code?/1)
      |> Enum.reject(&test_support?/1)
      |> Enum.map(fn module -> {module, count(module)} end)

    covered = counts |> Enum.map(fn {_module, {covered, _relevant}} -> covered end) |> Enum.sum()
    relevant = counts |> Enum.map(fn {_module, {_covered, relevant}} -> relevant end) |> Enum.sum()

    untouched =
      counts
      |> Enum.map(fn {module, {covered, relevant}} -> {relevant, covered, module} end)
      |> Enum.filter(fn {relevant, covered, _module} -> relevant > 0 and covered == 0 end)
      |> Enum.sort(:desc)

    IO.puts("covered lines: #{covered}")
    IO.puts("relevant lines: #{relevant}")
    IO.puts("coverage: #{percentage(covered, relevant)}")
    IO.puts("modules with nothing covered: #{length(untouched)}")

    for {relevant, _covered, module} <- untouched do
      IO.puts("  #{relevant} lines  #{inspect(module)}")
    end
  end

  defp own_code?(module), do: String.starts_with?(Atom.to_string(module), "Elixir.ExGoCD")

  # Compiled only for tests, and exercised by the tests it exists for. The names
  # come from the directory because an imported module is not loaded, so it has
  # no compile info to ask.
  defp test_support?(module) do
    name = module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
    MapSet.member?(test_support_modules(), name)
  end

  defp test_support_modules do
    "test/support/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      ~r/^defmodule ([\w.]+)/m
      |> Regex.scan(File.read!(path), capture: :all_but_first)
      |> List.flatten()
    end)
    |> MapSet.new()
  end

  defp count(module) do
    {:ok, lines} = :cover.analyse(module, :calls, :line)

    Enum.reduce(lines, {0, 0}, fn {line, calls}, {covered, relevant} ->
      tally(line, calls, covered, relevant)
    end)
  end

  # `:cover` files what a module runs when it loads — a `use`, a behaviour
  # declaration — under line 0. A source file has no line 0, so that is a marker
  # rather than a line, and counting it would make a module with nothing to cover
  # look like a module no test reaches.
  defp tally(0, _calls, covered, relevant), do: {covered, relevant}

  # A line with no calls recorded is a line no test ran.
  defp tally(_line, calls, covered, relevant) when calls > 0, do: {covered + 1, relevant + 1}
  defp tally(_line, _calls, covered, relevant), do: {covered, relevant + 1}

  defp percentage(_covered, 0), do: "—"
  defp percentage(covered, relevant), do: "#{Float.round(covered / relevant * 100, 1)} %"

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

CoverageTotal.run()
