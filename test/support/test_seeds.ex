defmodule ExGoCD.TestSeeds do
  @moduledoc """
  Fills the sandbox with the pipeline configuration a deploy starts with, by
  evaluating `priv/repo/seeds.exs` — the script `Release.seed/0` runs.

  The script is evaluated in the caller's process rather than through
  `Release.seed/0`, which opens its own connection and would commit, leaving the
  test database seeded for the next test.

  Returns what the script printed, for tests that care what it reports.
  """

  @seeds "priv/repo/seeds.exs"

  @spec seed() :: String.t()
  def seed do
    ExUnit.CaptureIO.capture_io(fn -> Code.eval_file(@seeds) end)
  end
end
