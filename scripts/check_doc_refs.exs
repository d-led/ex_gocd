#!/usr/bin/env elixir
# Checks that what the documentation points at still exists.
#
#   * every source file named in docs/PARITY.md is in lib/
#   * every /api/... path named there has a matching route in the router
#   * every relative markdown link in docs/ and README.md resolves to a file
#
# Run with: elixir scripts/check_doc_refs.exs

defmodule DocRefs do
  @parity "docs/PARITY.md"
  @router "lib/ex_gocd_web/router.ex"

  def main do
    problems = source_ref_problems() ++ link_problems()

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
    lib_files = Path.wildcard("lib/**/*.ex") |> Enum.map(&Path.basename/1) |> MapSet.new()

    @parity
    |> File.read!()
    |> table_cells()
    |> Enum.flat_map(&cell_problems(&1, router, lib_files))
  end

  defp table_cells(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "| "))
    |> Enum.flat_map(fn row ->
      row
      |> String.trim("|")
      |> String.split("|")
      |> Enum.map(&String.trim/1)
    end)
  end

  defp cell_problems(cell, router, lib_files) do
    module_problems(cell, lib_files) ++ route_problems(cell, router)
  end

  defp module_problems(cell, lib_files) do
    ~r/[\w\/]+\.ex/
    |> Regex.scan(cell)
    |> List.flatten()
    |> Enum.reject(fn reference ->
      name = Path.basename(reference)
      MapSet.member?(lib_files, name) or File.exists?(reference)
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

  defp link_problems do
    (["README.md" | Path.wildcard("docs/*.md")]
     |> Enum.uniq()
     |> Enum.flat_map(&links_in/1))
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
