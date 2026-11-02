defmodule TestDatabase do
  @moduledoc false

  @doc """
  Fails early, with an actionable message, when the schema has not been applied.

  Creating and migrating the database used to be part of `mix test` itself,
  which made two concurrent runs race on `CREATE DATABASE`. It is a one-time
  setup step instead: run `mix test.setup` once, then `mix test` as often, and
  as concurrently, as you like — the sandbox keeps each test's data to itself.
  """
  def ensure_ready! do
    case Ecto.Adapters.SQL.query(ExGoCD.Repo, "SELECT version FROM schema_migrations LIMIT 1", []) do
      {:ok, %{rows: [_ | _]}} -> :ok
      {:ok, %{rows: []}} -> unavailable!("the schema has no migrations applied")
      {:error, error} -> unavailable!(Exception.message(error))
    end
  end

  defp unavailable!(reason) do
    Mix.raise("""
    The test database is not ready: #{reason}

    Prepare it once with:

        mix test.setup

    To use a database that already exists elsewhere, set PGHOST/PGPORT (and
    PGUSER/PGPASSWORD if needed), or set DATABASE_URL.
    """)
  end
end

ExUnit.configure(max_cases: max(1, div(System.schedulers_online(), 2)))

# With EX_GOCD_TEST_NO_DB=1 the application starts without ExGoCD.Repo, so tests
# that need the database must be skipped rather than allowed to fail. DB-backed
# tests are tagged by ExGoCD.DataCase and ExGoCDWeb.ConnCase.
without_db? = System.get_env("EX_GOCD_TEST_NO_DB") == "1"

if without_db? do
  IO.puts("EX_GOCD_TEST_NO_DB=1: excluding tests tagged :database")
end

if System.get_env("CI") do
  ExUnit.configure(
    formatters: [ExUnit.CLIFormatter, JUnitFormatter],
    junit_formatter: [report_dir: "_build/test/lib/ex_gocd"]
  )
end

ExUnit.start(exclude: if(without_db?, do: [:database], else: []))

unless without_db? do
  TestDatabase.ensure_ready!()

  # :manual ownership. Each test checks out its own connection through
  # ExGoCD.DataCase.setup_sandbox/1 — shared with every process for a
  # synchronous test, private to the test process for an async one. Nothing is
  # shared behind the test's back, so the data one test writes is invisible to
  # any other and is rolled back with it.
  Ecto.Adapters.SQL.Sandbox.mode(ExGoCD.Repo, :manual)
end
