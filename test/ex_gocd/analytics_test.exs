defmodule ExGoCD.AnalyticsTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Analytics
  alias ExGoCD.Pipelines.{
    Job,
    JobInstance,
    Pipeline,
    PipelineInstance,
    Stage,
    StageInstance
  }

  @now ~U[2026-06-21 10:00:00Z]

  describe "pipeline_analytics/2 avg_wait_time" do
    setup do
      pipeline =
        Pipeline.changeset(%Pipeline{}, %{name: "wait-test-pipeline"})
        |> Repo.insert!()

      stage =
        Stage.changeset(%Stage{}, %{name: "build", pipeline_id: pipeline.id})
        |> Repo.insert!()

      job =
        Job.changeset(%Job{}, %{name: "compile", stage_id: stage.id})
        |> Repo.insert!()

      %{pipeline: pipeline, stage: stage, job: job}
    end

    test "returns avg wait time = assigned_at - inserted_at for first stage jobs" do
      # Pipeline triggered at T+0
      pi =
        insert_pipeline_instance("wait-test-pipeline", 1, @now)

      si =
        insert_stage_instance(pi.id, "build", ~U[2026-06-21 10:00:00Z])

      _ji =
        insert_job_instance(si.id, "compile", ~U[2026-06-21 10:00:00Z], ~U[2026-06-21 10:02:00Z])

      # wait = 10:02 - 10:00 = 120s
      result = Analytics.pipeline_analytics("wait-test-pipeline", 30)

      assert result.avg_wait_time_sec == 120.0
    end

    test "averages wait times across multiple pipeline instances" do
      # Instance 1: wait 60s
      pi1 =
        insert_pipeline_instance("wait-test-pipeline", 1, @now)

      si1 =
        insert_stage_instance(pi1.id, "build", @now)

      insert_job_instance(si1.id, "compile", @now, DateTime.add(@now, 60, :second))

      # Instance 2: wait 180s
      pi2 =
        insert_pipeline_instance("wait-test-pipeline", 2, DateTime.add(@now, 300, :second))

      si2 =
        insert_stage_instance(pi2.id, "build", DateTime.add(@now, 300, :second))

      insert_job_instance(si2.id, "compile", DateTime.add(@now, 300, :second), DateTime.add(@now, 480, :second))

      result = Analytics.pipeline_analytics("wait-test-pipeline", 30)

      assert result.avg_wait_time_sec == 120.0
    end

    test "uses earliest assigned_at among jobs in first stage" do
      pi =
        insert_pipeline_instance("wait-test-pipeline", 1, @now)

      si =
        insert_stage_instance(pi.id, "build", @now)

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
        insert_pipeline_instance("wait-test-pipeline", 1, @now)

      si =
        insert_stage_instance(pi.id, "build", @now)

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
        insert_pipeline_instance("wait-test-pipeline", 1, @now)

      si =
        insert_stage_instance(pi.id, "build", @now)

      # All assigned at same time as trigger → 0s wait, should be filtered out
      insert_job_instance(si.id, "compile", @now, @now)

      result = Analytics.pipeline_analytics("wait-test-pipeline", 30)

      assert is_nil(result.avg_wait_time_sec)
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────

  defp insert_pipeline_instance(name, counter, inserted_at) do
    pipeline = Repo.get_by!(Pipeline, name: name)
    Repo.insert!(%PipelineInstance{
      counter: counter,
      label: to_string(counter),
      natural_order: counter * 1.0,
      build_cause: %{"approver" => "test"},
      pipeline_id: pipeline.id,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end

  defp insert_stage_instance(pipeline_instance_id, name, inserted_at) do
    Repo.insert!(%StageInstance{
      name: name,
      counter: 1,
      order_id: 1,
      state: "Building",
      result: "Passed",
      approval_type: "success",
      created_time: inserted_at,
      pipeline_instance_id: pipeline_instance_id,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end

  defp insert_job_instance(stage_instance_id, name, scheduled_at, assigned_at) do
    Repo.insert!(%JobInstance{
      name: name,
      state: "Completed",
      result: "Passed",
      scheduled_at: DateTime.to_naive(scheduled_at),
      assigned_at: DateTime.to_naive(assigned_at),
      completed_at: DateTime.to_naive(DateTime.add(assigned_at, 60, :second)),
      stage_instance_id: stage_instance_id,
      inserted_at: scheduled_at,
      updated_at: assigned_at
    })
  end

  defp insert_job_instance_unassigned(stage_instance_id, name, scheduled_at) do
    Repo.insert!(%JobInstance{
      name: name,
      state: "Scheduled",
      result: "Unknown",
      scheduled_at: DateTime.to_naive(scheduled_at),
      assigned_at: nil,
      completed_at: nil,
      stage_instance_id: stage_instance_id,
      inserted_at: scheduled_at,
      updated_at: scheduled_at
    })
  end
end
