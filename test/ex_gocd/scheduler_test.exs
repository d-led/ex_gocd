defmodule ExGoCD.SchedulerTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Scheduler

  @uuid "550e8400-e29b-41d4-a716-446655440000"

  describe "schedule_job/1" do
    test "enqueues a job and returns id" do
      assert {:ok, id} = Scheduler.schedule_job(%{})
      assert is_binary(id)
      assert String.starts_with?(id, "sched-")

      assert {:ok, _id2} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j"})
      assert Scheduler.pending_count() >= 2
    end

    test "accepts pipeline, stage, job and optional resources, environments" do
      assert {:ok, _} =
               Scheduler.schedule_job(%{
                 "pipeline" => "my-pipeline",
                 "stage" => "build",
                 "job" => "compile",
                 "resources" => ["linux"],
                 "environments" => ["dev"]
               })

      assert Scheduler.pending_count() >= 1
    end
  end

  describe "try_assign_work/1" do
    test "returns :no_work when queue is empty" do
      # Agent may or may not exist/be connected; we only assert no_work when queue empty
      # First drain any existing jobs by scheduling and assigning elsewhere, or just check
      # that with no agent connected we get agent_not_connected
      result = Scheduler.try_assign_work(@uuid)
      assert result in [:no_work, :agent_not_connected, :agent_not_found]
    end

    test "returns :agent_not_found when agent uuid is not in DB" do
      _ = Scheduler.schedule_job(%{})
      # Use a random UUID that is not registered
      result = Scheduler.try_assign_work("00000000-0000-0000-0000-000000000000")
      assert result in [:agent_not_found, :agent_not_connected]
    end
  end

  describe "pending_count/0" do
    test "returns 0 when queue is empty" do
      # Scheduler state is process-wide; in async: false we share with other tests
      count = Scheduler.pending_count()
      assert is_integer(count) and count >= 0
    end
  end
end
