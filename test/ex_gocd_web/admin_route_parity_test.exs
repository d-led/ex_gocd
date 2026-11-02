defmodule ExGoCDWeb.AdminRouteParityTest do
  @moduledoc """
  The admin API is served twice: under `/api/admin`, and under `/go/api/admin`,
  which is the spelling api.go.cd documents. A route in one tree and not the
  other is invisible to whoever reads the documentation — the config repo API and
  the role config API were both in that state, and both answered 404 at the path
  a GoCD client is told to call.

  `/config_repos/cleanup` is one exception and stays one: it deletes data for
  tests, and a destructive hook does not need a second door.
  """
  use ExUnit.Case, async: true

  @deliberately_unmirrored [{"delete", "/config_repos/cleanup"}]

  test "the go-prefixed tree serves every route the plain tree serves" do
    assert Enum.sort(MapSet.to_list(missing_from("/go/api/admin"))) ==
             Enum.sort(@deliberately_unmirrored)
  end

  test "the plain tree serves every route the go-prefixed tree serves" do
    assert MapSet.size(missing_from("/api/admin")) == 0
  end

  defp missing_from(prefix) do
    MapSet.difference(routes("/api/admin"), routes(prefix))
  end

  defp routes(prefix) do
    for %{verb: verb, path: path} <- ExGoCDWeb.Router.__routes__(),
        String.starts_with?(path, prefix),
        into: MapSet.new(),
        do: {to_string(verb), String.replace_prefix(path, prefix, "")}
  end
end
