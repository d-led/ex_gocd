defmodule ExGoCD.Sweep do
  @moduledoc """
  Asks many paths for an answer and reports every one that does not give one.

  Written for the three sweeps that hold the endpoints, the routes and the pages
  to the same promise — that none of them falls over on a database with nothing in
  it. Each sweep knows what an answer looks like for it; this collects the
  offenders, keeps a raise as a sentence rather than a crash, and names all of
  them in one failure so a run does not have to be repeated per path.
  """
  import ExUnit.Assertions

  @doc """
  Fetches each of `paths` and asserts every one answered.

  `fetch` is called with a path and may raise. `answered?` decides whether what it
  returned counts as an answer, defaulting to "not a 5xx".
  """
  def assert_all_answered(paths, fetch, answered? \\ &response_under_500?/1) do
    offenders =
      Enum.flat_map(paths, fn path ->
        case attempt(fetch, path, answered?) do
          :answered -> []
          complaint -> [complaint]
        end
      end)

    assert offenders == [],
           "paths that did not answer:\n" <> Enum.join(offenders, "\n")
  end

  defp attempt(fetch, path, answered?) do
    result = fetch.(path)
    if answered?.(result), do: :answered, else: "#{path} answered #{inspect(result)}"
  rescue
    error -> "#{path} raised #{inspect(error.__struct__)}: #{Exception.message(error)}"
  end

  defp response_under_500?(%{status: status}), do: status < 500
end
