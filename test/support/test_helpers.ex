defmodule ExGoCD.TestHelpers do
  @moduledoc """
  Shared test helper functions extracted from duplicated `defp` patterns
  across multiple test files (http_test_agent_test, test_agent_test, etc.).
  """

  import ExUnit.Assertions, only: [flunk: 1]

  @doc """
  Retries a zero-arity function up to `retries` times with `sleep_ms` between attempts.
  If the function never returns a truthy value, flunks the test.
  """
  def assert_receive_or_retry(retries, func, sleep_ms \\ 100) do
    if func.() do
      true
    else
      if retries > 0 do
        Process.sleep(sleep_ms)
        assert_receive_or_retry(retries - 1, func, sleep_ms)
      else
        flunk("Assertion failed after retries")
      end
    end
  end

  @doc """
  Waits for the ExGoCD.Scheduler process to be registered and alive.
  Polls every 10ms until found or the test process dies.
  """
  def wait_for_scheduler do
    case Process.whereis(ExGoCD.Scheduler) do
      nil ->
        Process.sleep(10)
        wait_for_scheduler()

      pid ->
        if Process.alive?(pid) do
          :ok
        else
          Process.sleep(10)
          wait_for_scheduler()
        end
    end
  end
end
