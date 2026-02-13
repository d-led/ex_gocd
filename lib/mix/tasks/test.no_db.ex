defmodule Mix.Tasks.Test.NoDb do
  @shortdoc "Run tests without starting Postgres (skips ecto.create/ecto.migrate)"
  @moduledoc """
  Runs the test task only. Use with EX_GOCD_TEST_NO_DB=1 when Postgres is not available.

  Example:
      EX_GOCD_TEST_NO_DB=1 mix test.no_db
      EX_GOCD_TEST_NO_DB=1 mix test.no_db test/mix/tasks/convert_gocd_css_test.exs
  """
  use Mix.Task

  def run(args) do
    # Call the test task module directly so we don't trigger the "test" alias (ecto.create, ecto.migrate)
    Mix.Tasks.Test.run(args)
  end
end
