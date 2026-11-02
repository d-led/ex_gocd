defmodule ExGoCDWeb.PluginLiveTest do
  @moduledoc """
  The plugin dashboard answers two questions: is an agent-selector plugin
  registered, and what has the sample scheduling plugin decided lately. A page
  that calls itself "active" when nothing is registered is worse than a page with
  nothing on it, so the status is read from the registry.
  """
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ExGoCD.Plugin.Registry

  defmodule TestSelector do
    def select_candidates(agents, _spec, _opts), do: {:ok, agents}
  end

  setup do
    unregister()
    on_exit(&unregister/0)
    :ok
  end

  test "says nothing is registered when nothing is", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins")

    assert text_of(view, "#plugin-name") == "No agent_selector plugin registered"
    assert text_of(view, "#plugin-status") == "none"
  end

  test "names the registered plugin and calls it active", %{conn: conn} do
    register(TestSelector)

    {:ok, view, _html} = live(conn, ~p"/admin/plugins")

    assert text_of(view, "#plugin-name") =~ "TestSelector"
    assert text_of(view, "#plugin-status") == "active"
  end

  test "says there is nothing to show when no decisions have been made", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/plugins")

    assert html =~ "No scheduling decisions yet."
    assert html =~ "Scheduling Decisions"
  end

  defp text_of(view, selector) do
    view |> element(selector) |> render() |> String.trim() |> strip_tags()
  end

  defp strip_tags(html), do: String.replace(html, ~r/<[^>]*>/, "") |> String.trim()

  defp register(module) do
    :sys.replace_state(Registry, fn state ->
      state
      |> put_in([:slots, :agent_selector], module)
      |> put_in([:nodes, :agent_selector], node())
    end)
  end

  defp unregister do
    :sys.replace_state(Registry, fn state ->
      state
      |> put_in([:slots, :agent_selector], nil)
      |> put_in([:nodes, :agent_selector], nil)
    end)
  end
end
