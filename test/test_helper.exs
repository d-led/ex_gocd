if System.get_env("CI") do
  ExUnit.configure(
    formatters: [ExUnit.CLIFormatter, JUnitFormatter],
    junit_formatter: [report_dir: "_build/test-results"]
  )
end

ExUnit.configure(max_cases: max(1, div(System.schedulers_online(), 2)))
ExUnit.start()


# When running without Postgres (EX_GOCD_TEST_NO_DB=1), Repo is not started; skip sandbox.
if System.get_env("EX_GOCD_TEST_NO_DB") != "1" do
  Ecto.Adapters.SQL.Sandbox.mode(ExGoCD.Repo, :manual)
end
