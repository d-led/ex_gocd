defmodule Mix.Tasks.Test.WithDb do
  @shortdoc "Run ecto.create, ecto.migrate, then test (default test flow with Postgres)"
  @moduledoc """
  Runs ecto.create, ecto.migrate, then the test task. This is what the `test` alias
  uses so that `mix test` prepares the DB before running tests.
  """
  use Mix.Task

  def run(args) do
    Mix.Task.run("ecto.create", ["--quiet"])
    Mix.Task.run("ecto.migrate", ["--quiet"])
    # Call the test task module directly so we don't re-trigger the "test" alias
    Mix.Tasks.Test.run(args)
  end
end
