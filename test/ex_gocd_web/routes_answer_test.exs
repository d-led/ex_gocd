defmodule ExGoCDWeb.RoutesAnswerTest do
  @moduledoc """
  A route declares a module and an action. Phoenix dispatch calls that action, so
  a route whose action does not exist compiles, lists in `mix phx.routes`, passes
  any sweep that only asks paths the controller happens to implement — and raises
  `UndefinedFunctionError` for the one verb nobody exercised.

  `resources "/pipeline_groups", ..., except: [:new, :edit]` declared PUT with no
  `update/2` behind it, which is how this was found.

  LiveView routes name their module directly and mount it rather than calling an
  action, so they are not held to this.
  """
  use ExUnit.Case, async: true

  test "every routed action exists in the module the route names" do
    assert actions_missing() == []
  end

  defp actions_missing do
    for %{plug: module, plug_opts: action, verb: verb, path: path} <-
          ExGoCDWeb.Router.__routes__(),
        is_atom(module) and is_atom(action),
        not live_view?(module),
        not answers?(module, action),
        do: String.upcase(to_string(verb)) <> " #{path} → #{inspect(module)}.#{action}/2"
  end

  defp answers?(module, action) do
    Code.ensure_loaded?(module) and function_exported?(module, action, 2)
  end

  defp live_view?(module) do
    module == Phoenix.LiveView.Plug or function_exported?(module, :__live__, 0)
  end
end
