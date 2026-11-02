defmodule ExGoCD.Mcp.ArgsTest do
  use ExUnit.Case, async: true

  alias ExGoCD.Mcp.Args

  describe "required/2" do
    test "refuses a blank value" do
      assert Args.required(%{"name" => "  "}, "name") == {:error, "`name` is required."}
      assert Args.required(%{}, "name") == {:error, "`name` is required."}
    end

    test "accepts a number as the string it is" do
      assert Args.required(%{"counter" => 12}, "counter") == {:ok, "12"}
    end
  end

  describe "integer/3" do
    test "clamps rather than failing a number that is merely too large" do
      assert Args.integer(%{"limit" => 500}, "limit", default: 10, min: 1, max: 100) == {:ok, 100}
    end

    test "reads a number a client sent as text" do
      assert Args.integer(%{"limit" => "25"}, "limit", default: 10) == {:ok, 25}

      assert Args.integer(%{"limit" => "many"}, "limit", default: 10) ==
               {:error, "`limit` must be an integer."}
    end

    test "uses the default when the argument is absent" do
      assert Args.integer(%{}, "limit", default: 10) == {:ok, 10}
    end
  end

  describe "required_integer/2" do
    test "refuses absence rather than guessing a counter" do
      assert Args.required_integer(%{}, "counter") == {:error, "`counter` is required."}
      assert Args.required_integer(%{"counter" => "3"}, "counter") == {:ok, 3}
    end
  end

  describe "boolean/2" do
    test "reads a confirmation strictly: only a yes is a yes" do
      assert Args.boolean(%{"confirm" => "yes"}, "confirm") == {:ok, true}
      assert Args.boolean(%{"confirm" => "false"}, "confirm") == {:ok, false}
      assert Args.boolean(%{"confirm" => 0}, "confirm") == {:ok, false}

      assert Args.boolean(%{"confirm" => "maybe"}, "confirm") ==
               {:error, "`confirm` must be true or false."}
    end

    test "is false when absent, and required_boolean refuses that" do
      assert Args.boolean(%{}, "confirm") == {:ok, false}
      assert Args.required_boolean(%{}, "confirm") == {:error, "`confirm` is required."}
    end
  end

  describe "strings/2 and optional_strings/2" do
    test "reads one value, a list, or a comma-separated string" do
      assert Args.strings(%{"r" => "docker, linux"}, "r") == {:ok, ["docker", "linux"]}
      assert Args.strings(%{"r" => ["docker", " linux "]}, "r") == {:ok, ["docker", "linux"]}
      assert Args.strings(%{}, "r") == {:ok, []}
    end

    test "absent and empty are different answers" do
      assert Args.optional_strings(%{}, "resources") == {:ok, nil}
      assert Args.optional_strings(%{"resources" => []}, "resources") == {:ok, []}
    end
  end

  describe "objects/2" do
    test "refuses a list of things that are not objects" do
      assert Args.objects(%{"materials" => ["git"]}, "materials") ==
               {:error, "`materials` must be a list of JSON objects."}
    end
  end

  describe "date/2" do
    test "reads a day, and says what a day looks like" do
      assert Args.date(%{"from" => "2026-11-02"}, "from") == {:ok, ~D[2026-11-02]}

      assert Args.date(%{"from" => "yesterday"}, "from") ==
               {:error, "`from` must be a date, as `YYYY-MM-DD`."}

      assert Args.date(%{}, "from") == {:ok, nil}
    end
  end
end
