# Prints the endpoints api.go.cd documents that this server does not route.
#
#   mix run --no-start scripts/api_gap.exs
#
# The router's route table is compile-time data, so the application does not have
# to boot (and no database has to exist) for this to answer.
# The docs are a sibling checkout, so this reports only where they are present
# and says so when they are not — it never guesses a path.
#
# Paths are compared with their parameters erased (`:id`, `:plugin_id` — both
# sides become `*`), because the docs name the parameter and the router names
# the one it prefers.

docs_dir =
  Path.expand(
    System.get_env("API_DOCS_DIR", "../../api.go.cd/source/includes"),
    __DIR__
  )

unless File.dir?(docs_dir) do
  IO.puts("api.go.cd not found at #{docs_dir} — nothing to compare against.")
  System.halt(0)
end

documented =
  docs_dir
  |> Path.join("**/*.erb")
  |> Path.wildcard()
  |> Enum.flat_map(fn file ->
    ~r/\b(GET|POST|PUT|PATCH|DELETE)\s+(\/go\/api\/[^\s`'"]+)/
    |> Regex.scan(File.read!(file))
    |> Enum.map(fn [_, verb, path] -> {verb, path} end)
  end)
  |> Enum.uniq()

routed =
  ExGoCDWeb.Router.__routes__()
  |> Enum.map(&{&1.verb |> to_string() |> String.upcase(), &1.path})

defmodule Gap do
  @doc """
  Erases whatever distinguishes one path from another in shape only: parameters,
  the query string, and the docs' occurrence brackets.
  """
  def shape(path) do
    path
    |> String.split("?")
    |> hd()
    |> String.replace(~r/\[(\/\*)?\]$/, "/\\1")
    |> String.trim_trailing(".,)")
    |> String.replace(~r/:([A-Za-z_]+)/, "*")
    |> String.replace(~r/\*{2,}/, "*")
  end

  @doc "GoCD documents `/go/api/...`; we answer both that and `/api/...`."
  def spellings(path), do: [path, String.replace_prefix(path, "/go/api", "/api")]
end

routed_shapes = MapSet.new(routed, fn {verb, path} -> {verb, Gap.shape(path)} end)

covered? = fn {verb, path} ->
  path |> Gap.spellings() |> Enum.any?(&MapSet.member?(routed_shapes, {verb, Gap.shape(&1)}))
end

missing =
  documented
  |> Enum.reject(covered?)
  |> Enum.sort_by(fn {verb, path} -> {path, verb} end)

IO.puts("#{length(documented)} documented, #{length(missing)} not routed:\n")

Enum.each(missing, fn {verb, path} -> IO.puts("  #{verb} #{path}") end)
