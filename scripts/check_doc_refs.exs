#!/usr/bin/env elixir
# Checks that what the documentation points at still exists.
#
#   * every source file and /api route named in docs/PARITY.md
#   * every Elixir module named in docs/module_mapping.md
#   * every relative markdown link in docs/ and README.md
#
# Run with: elixir scripts/check_doc_refs.exs

defmodule DocRefs do
  @parity "docs/PARITY.md"
  @module_mapping "docs/module_mapping.md"
  @router "lib/ex_gocd_web/router.ex"

  def main do
    # The paths below are relative to the project, so it does not matter where
    # this is run from.
    File.cd!(Path.expand("..", __DIR__))

    problems = source_ref_problems() ++ named_module_problems() ++ link_problems()

    case problems do
      [] ->
        IO.puts("[PASS] documentation references resolve")
        exit({:shutdown, 0})

      list ->
        IO.puts("[FAIL] #{length(list)} documentation reference(s) resolve to nothing:")

        Enum.each(list, fn {file, reference, why} ->
          IO.puts("  #{file}: #{reference} — #{why}")
        end)

        exit({:shutdown, 1})
    end
  end

  # A feature table that names a module or a route is a claim that the thing is
  # there; these are the claims that can be read without judgement.
  defp source_ref_problems do
    router = File.read!(@router)
    names = Path.wildcard("lib/**/*.ex") |> Enum.map(&Path.basename/1) |> MapSet.new()

    @parity
    |> File.read!()
    |> table_cells()
    |> Enum.flat_map(&cell_problems(&1, router, names))
  end

  defp table_cells(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "| "))
    |> Enum.flat_map(fn row ->
      row |> String.trim("|") |> String.split("|") |> Enum.map(&String.trim/1)
    end)
  end

  defp cell_problems(cell, router, names) do
    file_problems(cell, names) ++ route_problems(cell, router)
  end

  defp file_problems(cell, names) do
    ~r/[\w\/]+\.ex/
    |> Regex.scan(cell)
    |> List.flatten()
    |> Enum.reject(fn reference ->
      MapSet.member?(names, Path.basename(reference)) or File.exists?(reference)
    end)
    |> Enum.map(&{@parity, &1, "no such source file"})
  end

  defp route_problems(cell, router) do
    ~r/\/api\/[\w\/]+/
    |> Regex.scan(cell)
    |> List.flatten()
    |> Enum.reject(fn route ->
      route
      |> String.split("/")
      |> Enum.drop(2)
      |> Enum.reject(&String.contains?(&1, ":"))
      |> Enum.all?(&String.contains?(router, &1))
    end)
    |> Enum.map(&{@parity, &1, "no such route"})
  end

  # The mapping names the Elixir module beside each GoCD source file. A module
  # that was renamed or removed leaves a claim nothing answers.
  defp named_module_problems do
    defined = defined_modules()

    @module_mapping
    |> File.read!()
    |> then(&Regex.scan(~r/`(ExGoCD[\w.]*)`/, &1))
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(defined, &1))
    |> Enum.map(&{@module_mapping, &1, "no such module"})
  end

  defp defined_modules do
    Path.wildcard("lib/**/*.ex")
    |> Enum.flat_map(fn file -> Regex.scan(~r/defmodule\s+([\w.]+)/, File.read!(file)) end)
    |> Enum.map(fn [_, name] -> name end)
    |> MapSet.new()
  end

  defp link_problems do
    (["README.md" | Path.wildcard("docs/*.md")] |> Enum.uniq())
    |> Enum.flat_map(&links_in/1)
  end

  defp links_in(file) do
    base = Path.dirname(file)

    file
    |> File.read!()
    |> then(&Regex.scan(~r/\[[^\]]*\]\(([^)]+)\)/, &1))
    |> Enum.map(&List.last/1)
    |> Enum.map(&(&1 |> String.split("#") |> hd()))
    |> Enum.reject(&(external?(&1) or &1 == ""))
    |> Enum.reject(&File.exists?(Path.join(base, &1)))
    |> Enum.map(&{file, &1, "link to a missing file"})
  end

  defp external?(link), do: String.starts_with?(link, ["http", "#", "mailto:"])
end

DocRefs.main()
