ExUnit.configure(max_cases: max(1, div(System.schedulers_online(), 2)))

if System.get_env("CI") do
  ExUnit.configure(
    formatters: [ExUnit.CLIFormatter, JUnitFormatter],
    junit_formatter: [report_dir: "_build/test/lib/ex_gocd"],
    exclude: [:ci_skip]
  )
end

ExUnit.start()

# Start the k8s DynamicHTTPProvider for disconnected testing
K8s.Client.DynamicHTTPProvider.start_link(nil)

# When running without Postgres (EX_GOCD_TEST_NO_DB=1), Repo is not started; skip sandbox.
if System.get_env("EX_GOCD_TEST_NO_DB") != "1" do
  # {:shared, pid} allows GenServer processes (Scheduler, Poller) to access DB
  # without DBConnection.OwnershipError. Uses self() which is the ExUnit runner.
  Ecto.Adapters.SQL.Sandbox.mode(ExGoCD.Repo, {:shared, self()})
end
