defmodule ExGoCD.SchedulingChecker.TriggerMonitorTest do
  @moduledoc """
  Tests for the ETS-based trigger dedup monitor.
  Behaviour-driven: given a pipeline name, mark_triggered prevents
  re-entry, already_triggered? returns correct state, mark_completed
  releases.
  """
  use ExUnit.Case, async: false

  alias ExGoCD.SchedulingChecker.TriggerMonitor

  setup do
    # Ensure table exists (lazy init)
    TriggerMonitor.mark_completed("cleanup-any")
    :ok
  end

  describe "already_triggered?/1" do
    test "returns false for never-seen pipeline" do
      refute TriggerMonitor.already_triggered?("brand-new-pipeline")
    end

    test "returns false for different pipeline names" do
      TriggerMonitor.mark_triggered("pipe-a")
      refute TriggerMonitor.already_triggered?("pipe-b")
    end
  end

  describe "mark_triggered/1" do
    test "first mark returns true (was not already in set)" do
      assert TriggerMonitor.mark_triggered("first-trigger")
      assert TriggerMonitor.already_triggered?("first-trigger")
    end

    test "second mark of same pipeline returns false (was already in set)" do
      TriggerMonitor.mark_triggered("double-trigger")
      refute TriggerMonitor.mark_triggered("double-trigger")
    end

    test "different pipelines don't interfere" do
      assert TriggerMonitor.mark_triggered("pipe-1")
      assert TriggerMonitor.mark_triggered("pipe-2")
      assert TriggerMonitor.mark_triggered("pipe-3")

      assert TriggerMonitor.already_triggered?("pipe-1")
      assert TriggerMonitor.already_triggered?("pipe-2")
      assert TriggerMonitor.already_triggered?("pipe-3")
    end
  end

  describe "mark_completed/1" do
    test "removes pipeline from triggered set" do
      TriggerMonitor.mark_triggered("to-complete")
      assert TriggerMonitor.already_triggered?("to-complete")

      TriggerMonitor.mark_completed("to-complete")
      refute TriggerMonitor.already_triggered?("to-complete")
    end

    test "completing never-triggered pipeline is a no-op" do
      assert TriggerMonitor.mark_completed("never-triggered") == :ok
      refute TriggerMonitor.already_triggered?("never-triggered")
    end

    test "complete and re-trigger cycle works" do
      assert TriggerMonitor.mark_triggered("cycle-pipe")
      TriggerMonitor.mark_completed("cycle-pipe")
      assert TriggerMonitor.mark_triggered("cycle-pipe")
      TriggerMonitor.mark_completed("cycle-pipe")
      refute TriggerMonitor.already_triggered?("cycle-pipe")
    end
  end

  describe "concurrency safety" do
    test "ETS table supports concurrent access from multiple processes" do
      parent = self()

      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            name = "concurrent-#{i}"
            result = TriggerMonitor.mark_triggered(name)
            send(parent, {:marked, name, result})
          end)
        end

      Task.await_many(tasks, 1000)

      results =
        for _ <- 1..20 do
          receive do
            {:marked, name, result} -> {name, result}
          after
            500 -> :timeout
          end
        end

      # All 20 unique names should have been successfully marked
      assert length(results) == 20
      assert Enum.all?(results, fn {_, result} -> result == true end)
      assert Enum.all?(results, fn {name, _} -> TriggerMonitor.already_triggered?(name) end)

      # Cleanup
      for {name, _} <- results, do: TriggerMonitor.mark_completed(name)
    end
  end
end
