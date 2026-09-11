defmodule ExGoCD.RemotingFixture do
  @moduledoc """
  Access to the captured GoCD agent remoting traffic in `test/fixtures/remoting`.

  These files are verbatim recordings of an official Java agent talking to an
  official GoCD server (see the fixture README for the capture procedure), so
  asserting against them pins the implementation to observed reality rather
  than to an interpretation of the Java sources.
  """

  @fixture_dir "test/fixtures/remoting"

  @doc """
  Reads a raw fixture file as a string.
  """
  def raw(name) when is_binary(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> String.trim_trailing("\n")
  end

  @doc """
  Reads a fixture file and decodes it as JSON.
  """
  def json(name) when is_binary(name) do
    name |> raw() |> Jason.decode!()
  end
end
