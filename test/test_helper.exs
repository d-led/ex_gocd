ExUnit.start()

# When running without Postgres (EX_GOCD_TEST_NO_DB=1), Repo is not started; skip sandbox.
if System.get_env("EX_GOCD_TEST_NO_DB") != "1" do
  Ecto.Adapters.SQL.Sandbox.mode(ExGoCD.Repo, :manual)
end
