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
    # Dependencies are compiled into the same export; only our own code counts.
    modules =
      :cover.imported_modules()
      |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "Elixir.ExGoCD"))

    {covered, relevant, untouched} =
      Enum.reduce(modules, {0, 0, 0}, fn module, {covered, relevant, untouched} ->
        {module_covered, module_relevant} = count(module)
        {covered + module_covered, relevant + module_relevant, untouched + untouched(module_relevant, module_covered)}
      end)

    IO.puts("covered lines: #{covered}")
    IO.puts("relevant lines: #{relevant}")
    IO.puts("coverage: #{percentage(covered, relevant)}")
    IO.puts("modules with nothing covered: #{untouched}")
  end

  defp count(module) do
    {:ok, lines} = :cover.analyse(module, :calls, :line)

    Enum.reduce(lines, {0, 0}, fn {_line, calls}, {covered, relevant} ->
      tally(calls, covered, relevant)
    end)
  end

  # A line with no calls recorded is a line no test ran.
  defp tally(calls, covered, relevant) when calls > 0, do: {covered + 1, relevant + 1}
  defp tally(_calls, covered, relevant), do: {covered, relevant + 1}

  defp untouched(0, _covered), do: 0
  defp untouched(_relevant, 0), do: 1
  defp untouched(_relevant, _covered), do: 0

  defp percentage(_covered, 0), do: "—"
  defp percentage(covered, relevant), do: "#{Float.round(covered / relevant * 100, 1)} %"

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

CoverageTotal.run()
