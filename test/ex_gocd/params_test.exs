defmodule ExGoCD.ParamsTest do
  @moduledoc """
  Tests for parameter interpolation and merging.

  GoCD parity: `\#{param}` syntax in pipeline labels, task commands,
  arguments, and environment variables.
  """
  use ExUnit.Case, async: true

  alias ExGoCD.Params

  describe "interpolate/2" do
    test "returns plain strings unchanged when no placeholders" do
      assert Params.interpolate("hello world", %{}) == "hello world"
    end

    test "replaces single placeholder with param value" do
      assert Params.interpolate("hello \#{name}", %{"name" => "world"}) == "hello world"
    end

    test "replaces multiple placeholders" do
      assert Params.interpolate("\#{greeting} \#{target}", %{
               "greeting" => "hello",
               "target" => "world"
             }) == "hello world"
    end

    test "leaves unknown placeholders unchanged" do
      assert Params.interpolate("\#{known} \#{unknown}", %{"known" => "yes"}) == "yes \#{unknown}"
    end

    test "passes through non-string values unchanged" do
      assert Params.interpolate(42, %{}) == 42
      assert Params.interpolate(nil, %{}) == nil
      assert Params.interpolate(true, %{}) == true
    end

    test "interpolates each element in a list" do
      assert Params.interpolate(["echo", "\#{msg}"], %{"msg" => "hi"}) == ["echo", "hi"]
    end

    test "interpolates values in a map" do
      assert Params.interpolate(%{"key" => "\#{val}"}, %{"val" => "replaced"}) == %{
               "key" => "replaced"
             }
    end

    test "handles deeply nested structures" do
      input = %{
        "args" => ["--name", "\#{name}", "--env", "\#{env}"],
        "nested" => %{"key" => "\#{value}"}
      }

      params = %{"name" => "app", "env" => "prod", "value" => "nested_val"}

      expected = %{
        "args" => ["--name", "app", "--env", "prod"],
        "nested" => %{"key" => "nested_val"}
      }

      assert Params.interpolate(input, params) == expected
    end

    test "converts param values to strings for interpolation" do
      assert Params.interpolate("\#{num}", %{"num" => 42}) == "42"
    end

    test "handles param names with underscores and digits" do
      assert Params.interpolate("\#{my_param_1}", %{"my_param_1" => "ok"}) == "ok"
    end
  end

  describe "merge_params/2" do
    test "merges pipeline params with option overrides" do
      assert Params.merge_params(%{"p1" => "v1"}, %{parameters: %{"p2" => "v2"}}) ==
               %{"p1" => "v1", "p2" => "v2"}
    end

    test "option overrides take precedence over pipeline defaults" do
      assert Params.merge_params(%{"p1" => "old"}, %{parameters: %{"p1" => "new"}}) ==
               %{"p1" => "new"}
    end

    test "handles nil pipeline params" do
      assert Params.merge_params(nil, %{parameters: %{"p1" => "v1"}}) ==
               %{"p1" => "v1"}
    end

    test "handles empty options" do
      assert Params.merge_params(%{"p1" => "v1"}, %{}) == %{"p1" => "v1"}
    end

    test "stringifies atom keys from pipeline params" do
      assert Params.merge_params(%{key: "value"}, %{}) == %{"key" => "value"}
    end

    test "accepts string-keyed parameters in options" do
      assert Params.merge_params(%{}, %{"parameters" => %{"p1" => "v1"}}) ==
               %{"p1" => "v1"}
    end
  end
end
