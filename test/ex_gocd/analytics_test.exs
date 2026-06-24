defmodule ExGoCD.AnalyticsTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Analytics

  import ExGoCD.PipelinesFixtures,
    only: [
      insert_pipeline_instance_by_name: 3,
      insert_stage_instance: 3,
      insert_job_instance: 4,
      insert_job_instance_unassigned: 3,
      insert_pipeline_with_jobs: 2
    ]

  @now ~U[2026-06-21 10:00:00.000000Z]

  describe "pipeline_analytics/2 avg_wait_time" do
    setup do
      {pipeline, stage, [job]} = insert_pipeline_with_jobs("wait-test-pipeline", 1)

      %{pipeline: pipeline, stage: stage, job: job}
    end

    test "returns avg wait time = assigned_at - inserted_at for first stage jobs" do
      # Pipeline triggered at T+0
      pi =
        insert_pipeline_instance_by_name("wait-test-pipeline", 1, @now)

      si =
        insert_stage_instance(pi.id, "build", created_time: @now)

      _ji =
        insert_job_instance(si.id, "compile", @now, DateTime.add(@now, 120, :second))

      # wait = 10:02 - 10:00 = 120s
      result = Analytics.pipeline_analytics("wait-test-pipeline", 30)

      assert result.avg_wait_time_sec == 120.0
    end

    test "averages wait times across multiple pipeline instances" do
      # Instance 1: wait 60s
      pi1 =
        insert_pipeline_instance_by_name("wait-test-pipeline", 1, @now)

      si1 =
        insert_stage_instance(pi1.id, "build", created_time: @now)

      insert_job_instance(si1.id, "compile", @now, DateTime.add(@now, 60, :second))

      # Instance 2: wait 180s
      pi2 =
        insert_pipeline_instance_by_name(
          "wait-test-pipeline",
          2,
          DateTime.add(@now, 300, :second)
        )

      si2 =
        insert_stage_instance(pi2.id, "build", created_time: DateTime.add(@now, 300, :second))

      insert_job_instance(
        si2.id,
        "compile",
        DateTime.add(@now, 300, :second),
        DateTime.add(@now, 480, :second)
      )

      result = Analytics.pipeline_analytics("wait-test-pipeline", 30)

      assert result.avg_wait_time_sec == 120.0
    end

    test "uses earliest assigned_at among jobs in first stage" do
      pi =
        insert_pipeline_instance_by_name("wait-test-pipeline", 1, @now)

      si =
        insert_stage_instance(pi.id, "build", created_time: @now)

      # Job A assigned later
      insert_job_instance(si.id, "compile", @now, DateTime.add(@now, 300, :second))
      # Job B assigned earlier
      insert_job_instance(si.id, "test", @now, DateTime.add(@now, 60, :second))

      result = Analytics.pipeline_analytics("wait-test-pipeline", 30)

      # Earliest assigned = 60s
      assert result.avg_wait_time_sec == 60.0
    end

    test "ignores instances where no job has been assigned yet" do
      # Instance with no agent assignment (assigned_at = nil)
      pi =
        insert_pipeline_instance_by_name("wait-test-pipeline", 1, @now)

      si =
        insert_stage_instance(pi.id, "build", created_time: @now)

      insert_job_instance_unassigned(si.id, "compile", @now)

      result = Analytics.pipeline_analytics("wait-test-pipeline", 30)

      assert is_nil(result.avg_wait_time_sec)
      assert result.run_count == 1
    end

    test "returns nil when there are no pipeline instances" do
      result = Analytics.pipeline_analytics("nonexistent-pipeline", 30)

      assert result.run_count == 0
      assert is_nil(result.avg_wait_time_sec)
    end

    test "filters out instances where wait time is zero or negative" do
      pi =
        insert_pipeline_instance_by_name("wait-test-pipeline", 1, @now)

      si =
        insert_stage_instance(pi.id, "build", created_time: @now)

      # All assigned at same time as trigger → 0s wait, should be filtered out
      insert_job_instance(si.id, "compile", @now, @now)

      result = Analytics.pipeline_analytics("wait-test-pipeline", 30)

      assert is_nil(result.avg_wait_time_sec)
    end
  end

  # ── Helpers kept: none — all moved to ExGoCD.PipelinesFixtures ──
end
