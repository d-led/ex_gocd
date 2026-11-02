defmodule ExGoCD.ReleaseTest do
  @moduledoc """
  `mix release` runs `Release.seed/0`, which evaluates `priv/repo/seeds.exs`. That
  script claims to be safe to run more than once — a deploy does not always start
  from an empty database, and a seed that duplicates rows turns a restore into a
  mess.

  The script is evaluated here in the test's sandbox rather than through
  `Release.seed/0`, which opens its own connection and would commit.
  """
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Repo
  alias ExGoCD.TestSeeds

  test "the seeds run on an empty database" do
    TestSeeds.seed()

    assert Repo.aggregate(Pipeline, :count) > 0
  end

  test "the seeds make no fake runs unless mock data was asked for" do
    report = TestSeeds.seed()

    assert Repo.aggregate(ExGoCD.Pipelines.PipelineInstance, :count) == 0
    refute report =~ "historical runs", "the report claims runs that were not made"
  end

  test "with mock data asked for, the seeds report and make the runs" do
    System.put_env("USE_MOCK_DATA", "true")
    on_exit(fn -> System.delete_env("USE_MOCK_DATA") end)

    report = TestSeeds.seed()

    assert Repo.aggregate(ExGoCD.Pipelines.PipelineInstance, :count) > 0
    assert report =~ "historical runs"
  end

  test "running the seeds again changes nothing" do
    TestSeeds.seed()
    first = counts()

    TestSeeds.seed()

    assert counts() == first
  end

  defp counts do
    %{
      pipelines: Repo.aggregate(Pipeline, :count),
      stages: Repo.aggregate(ExGoCD.Pipelines.Stage, :count),
      jobs: Repo.aggregate(ExGoCD.Pipelines.Job, :count),
      materials: Repo.aggregate(ExGoCD.Pipelines.Material, :count),
      users: Repo.aggregate(ExGoCD.Accounts.User, :count)
    }
  end
end
