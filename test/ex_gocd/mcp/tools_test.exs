defmodule ExGoCD.Mcp.ToolsTest do
  use ExUnit.Case, async: true

  alias ExGoCD.Mcp.Tools

  test "every declared tool answers to a handler" do
    for %{"name" => name} <- Tools.definitions() do
      assert Tools.handles?(name), "#{name} is declared but no family handles it"
    end
  end

  test "no family handles a name nobody declared" do
    declared = MapSet.new(Tools.definitions(), & &1["name"])

    for name <- Tools.names(), name not in declared do
      flunk("#{name} is handled but never declared")
    end
  end

  test "names are unique" do
    names = Enum.map(Tools.definitions(), & &1["name"])
    assert names == Enum.uniq(names)
  end

  test "every tool says what it is: a title, a description, a schema and honest annotations" do
    for tool <- Tools.definitions() do
      assert is_binary(tool["title"]) and tool["title"] != ""
      assert is_binary(tool["description"]) and String.length(tool["description"]) > 40
      assert tool["inputSchema"]["type"] == "object"
      assert is_boolean(tool["annotations"]["readOnlyHint"])
      assert is_boolean(tool["annotations"]["destructiveHint"])
    end
  end

  test "the writers are the tools that do not claim to be read-only" do
    writers = Tools.writers() |> Enum.map(& &1["name"])

    assert "gocd_trigger_pipeline" in writers
    assert "gocd_cancel_stage" in writers
    refute "gocd_list_pipelines" in writers
  end

  test "the families together are every tool, grouped the way a reader asks" do
    in_families = for {_label, tools} <- Tools.families(), tool <- tools, do: tool["name"]

    assert Enum.sort(in_families) == Tools.names()
  end

  test "an unknown tool is not handled, and a call says so" do
    refute Tools.handles?("gocd_nonexistent")
    assert Tools.call("gocd_nonexistent", %{}, %{}) == :unknown_tool
  end
end
