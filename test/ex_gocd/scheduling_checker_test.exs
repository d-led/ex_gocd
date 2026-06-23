defmodule ExGoCD.SchedulingCheckerTest do
  @moduledoc """
  Tests for the SchedulingChecker behaviour and Composite runner.
  Behaviour-driven: given a list of checkers, the composite runs them
  in order until one fails or all pass.
  """
  use ExUnit.Case, async: true

  alias ExGoCD.SchedulingChecker
  alias ExGoCD.SchedulingChecker.Composite

  defmodule PassingChecker do
    use SchedulingChecker

    @impl true
    def check(_pipeline_name), do: :ok
  end

  defmodule FailingChecker do
    use SchedulingChecker

    @impl true
    def check(_pipeline_name), do: {:error, :test_failure}
  end

  defmodule ContextChecker do
    use SchedulingChecker

    @impl true
    def check("allow-me"), do: :ok
    def check("deny-me"), do: {:error, :denied}
    def check(_), do: :ok
  end

  describe "Composite.check/2" do
    test "empty list returns :ok" do
      assert Composite.check([], "any-pipeline") == :ok
    end

    test "single passing checker returns :ok" do
      assert Composite.check([PassingChecker], "any") == :ok
    end

    test "single failing checker returns its error" do
      assert Composite.check([FailingChecker], "any") == {:error, :test_failure}
    end

    test "multiple passing checkers all run and return :ok" do
      assert Composite.check([PassingChecker, PassingChecker, PassingChecker], "any") == :ok
    end

    test "stops at first failure, subsequent checkers not called" do
      assert Composite.check([PassingChecker, FailingChecker, PassingChecker], "any") ==
               {:error, :test_failure}
    end

    test "passes pipeline_name to each checker" do
      assert Composite.check([ContextChecker], "allow-me") == :ok
      assert Composite.check([ContextChecker], "deny-me") == {:error, :denied}
      assert Composite.check([ContextChecker], "whatever") == :ok
    end

    test "checkers run in insertion order" do
      # First fails → stops there
      assert Composite.check([FailingChecker, PassingChecker], "any") == {:error, :test_failure}
      # First passes, second fails
      assert Composite.check([PassingChecker, FailingChecker], "any") == {:error, :test_failure}
    end
  end
end
