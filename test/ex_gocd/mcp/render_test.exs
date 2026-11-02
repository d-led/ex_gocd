defmodule ExGoCD.Mcp.RenderTest do
  use ExUnit.Case, async: true

  alias ExGoCD.Mcp.Render

  describe "table/2" do
    test "pads every column to its widest cell and leaves no trailing spaces" do
      assert Render.table(["NAME", "RUN"], [["build", 3], ["a", 12]]) == """
             NAME   RUN
             build  3
             a      12\
             """
    end

    test "shows an unknown value as an em dash rather than a zero" do
      assert Render.table(["STATE"], [[nil]]) == "STATE\n—"
    end
  end

  describe "duration/1" do
    test "reads as a person would say it" do
      assert Render.duration(9) == "9.0s"
      assert Render.duration(130) == "2m 10s"
      assert Render.duration(3_900) == "1h 05m"
      assert Render.duration(nil) == "—"
    end
  end

  describe "tail/2" do
    test "keeps the end of a long log and says how much was left out" do
      log = Enum.map_join(1..5, "\n", &"line #{&1}")

      assert Render.tail(log, 2) == "3 earlier line(s) not shown\nline 4\nline 5"
    end

    test "returns a short log whole" do
      assert Render.tail("one\ntwo", 5) == "one\ntwo"
    end
  end

  describe "truncate/2" do
    test "says when it cut something" do
      assert Render.truncate("abcdef", 3) == "abc… (truncated)"
      assert Render.truncate("abc", 3) == "abc"
    end
  end
end
