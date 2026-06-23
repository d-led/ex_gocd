defmodule ExGoCD.SchedulingChecker.AboutToBeTriggeredTest do
  @moduledoc """
  Tests for the debounce checker.
  Behaviour-driven: given a pipeline being triggered, a second trigger
  within the debounce window is rejected with :already_triggered.
  """
  use ExUnit.Case, async: false

  alias ExGoCD.SchedulingChecker.{AboutToBeTriggered, TriggerMonitor}

  setup do
    # Clean state before each test
    TriggerMonitor.mark_completed("debounce-pipe")
    TriggerMonitor.mark_completed("another-pipe")
    :ok
  end

  describe "check/1" do
    test "returns :ok when pipeline is not being triggered" do
      assert AboutToBeTriggered.check("fresh-pipeline") == :ok
    end

    test "returns {:error, :already_triggered} when pipeline is in triggered set" do
      TriggerMonitor.mark_triggered("debounce-pipe")
      assert AboutToBeTriggered.check("debounce-pipe") == {:error, :already_triggered}
    end

    test "different pipelines don't interfere" do
      TriggerMonitor.mark_triggered("debounce-pipe")
      assert AboutToBeTriggered.check("another-pipe") == :ok
    end

    test "after completion, pipeline can be triggered again" do
      TriggerMonitor.mark_triggered("debounce-pipe")
      assert AboutToBeTriggered.check("debounce-pipe") == {:error, :already_triggered}

      TriggerMonitor.mark_completed("debounce-pipe")
      assert AboutToBeTriggered.check("debounce-pipe") == :ok
    end
  end
end
