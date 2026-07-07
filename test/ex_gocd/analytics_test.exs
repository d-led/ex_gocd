defmodule ExGoCD.AnalyticsTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Analytics
  alias ExGoCD.Repo
  import Ecto.Query

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

  describe "agent_analytics/1" do
    test "returns empty list when no agent job runs exist" do
      result = Analytics.agent_analytics(7)
      assert result == []
    end
  end

  describe "agent_utilization/3" do
    test "returns 0.0 when no transitions exist" do
      start_dt = ~U[2026-01-01 00:00:00Z]
      end_dt = ~U[2026-01-02 00:00:00Z]
      util = Analytics.agent_utilization("unknown-uuid", start_dt, end_dt)
      assert util == 0.0
    end

    test "returns 0.0 when agent is always idle" do
      uuid = "cccc0000-e29b-41d4-a716-446655440003"
      start_dt = ~U[2026-01-01 00:00:00Z]
      end_dt = ~U[2026-01-01 01:00:00Z]

      Analytics.record_agent_transition(uuid, "Idle", "Idle")
      util = Analytics.agent_utilization(uuid, start_dt, end_dt)
      assert util == 0.0
    end

    test "returns utilization ratio when agent does work" do
      uuid = "dddd0000-e29b-41d4-a716-446655440004"
      start_dt = ~U[2026-01-01 00:00:00Z]
      mid_dt = ~U[2026-01-01 00:30:00Z]
      end_dt = ~U[2026-01-01 01:00:00Z]

      # Agent busy for 30 min of 60 min window → 0.5
      Analytics.record_agent_transition(uuid, "Idle", "Building")
      Analytics.record_agent_transition(uuid, "Building", "Idle")

      # Override transitioned_at to specific times
      Repo.update_all(
        from(t in ExGoCD.Analytics.AgentTransition,
          where: t.agent_uuid == ^uuid and t.to_state == "Building"
        ),
        set: [transitioned_at: start_dt]
      )

      Repo.update_all(
        from(t in ExGoCD.Analytics.AgentTransition,
          where: t.agent_uuid == ^uuid and t.to_state == "Idle"
        ),
        set: [transitioned_at: mid_dt]
      )

      util = Analytics.agent_utilization(uuid, start_dt, end_dt)
      assert util == 0.5
    end
  end

  describe "vsm_trends/2" do
    test "returns empty list when no pipeline instances exist" do
      result = Analytics.vsm_trends("no-such-pipeline", 30)
      assert result == []
    end

    test "returns VSM data for pipeline with stage instances" do
      {pipeline, _, _} = insert_pipeline_with_jobs("vsm-test-pipe", 1)

      pi = insert_pipeline_instance_by_name("vsm-test-pipe", 1, @now)
      si = insert_stage_instance(pi.id, "build", created_time: @now)

      insert_job_instance(si.id, "compile", @now, DateTime.add(@now, 60, :second))

      result = Analytics.vsm_trends("vsm-test-pipe", 30)

      assert length(result) == 1
      run = hd(result)
      assert run.counter == 1
      assert run.stage_count == 1
      assert length(run.stages) == 1
    end
  end

  describe "calc_mttr (Mean Time To Recovery)" do
    test "returns nil when all pipelines pass" do
      {pipeline, _, _} = insert_pipeline_with_jobs("mttr-all-pass", 1)

      pi1 = insert_pipeline_instance_by_name("mttr-all-pass", 1, @now)
      si1 = insert_stage_instance(pi1.id, "build", created_time: @now)
      insert_job_instance(si1.id, "compile", @now, DateTime.add(@now, 60, :second))
      # Mark stage as passed
      Repo.update_all(from(s in ExGoCD.Pipelines.StageInstance, where: s.id == ^si1.id),
        set: [result: "Passed"]
      )

      result = Analytics.pipeline_analytics("mttr-all-pass", 30)
      assert is_nil(result.mttr_sec)
    end
  end

  describe "avg_build_time" do
    test "returns nil when no completed stages exist" do
      {pipeline, _, _} = insert_pipeline_with_jobs("build-time-pipe", 1)

      pi = insert_pipeline_instance_by_name("build-time-pipe", 1, @now)
      _si = insert_stage_instance(pi.id, "build", created_time: @now)

      result = Analytics.pipeline_analytics("build-time-pipe", 30)
      assert is_nil(result.avg_build_time_sec)
    end
  end

  # ── VSM Workflow Trends & Time Distribution ──────────────────────

  describe "vsm_workflow_trends/3" do
    test "returns pipelines list with source pipeline" do
      {pipeline, _, _} = insert_pipeline_with_jobs("vsm-wf-source", 1)
      _pi = insert_pipeline_instance_by_name("vsm-wf-source", 1, @now)

      result = Analytics.vsm_workflow_trends("vsm-wf-source")

      assert result.pipelines == ["vsm-wf-source"]
    end

    test "returns workflows grouped by source pipeline runs" do
      {pipeline, _, _} = insert_pipeline_with_jobs("vsm-wf-trends", 1)

      t1 = @now
      t2 = DateTime.add(@now, 600, :second)

      pi1 = insert_pipeline_instance_by_name("vsm-wf-trends", 1, t1)
      si1 = insert_stage_instance(pi1.id, "build", created_time: t1)
      insert_job_instance(si1.id, "compile", t1, DateTime.add(t1, 60, :second))

      pi2 = insert_pipeline_instance_by_name("vsm-wf-trends", 2, t2)
      si2 = insert_stage_instance(pi2.id, "build", created_time: t2)
      insert_job_instance(si2.id, "compile", t2, DateTime.add(t2, 60, :second))

      result = Analytics.vsm_workflow_trends("vsm-wf-trends", nil, 10)

      assert length(result.workflows) == 2
      wf1 = Enum.find(result.workflows, &(&1.source_counter == 1))
      wf2 = Enum.find(result.workflows, &(&1.source_counter == 2))
      assert wf1 != nil
      assert wf2 != nil
      assert length(wf1.instances) == 1
      assert length(wf2.instances) == 1
    end

    test "each workflow instance has pipeline_name, counter, and stages" do
      {pipeline, _, _} = insert_pipeline_with_jobs("vsm-wf-instance", 1)

      pi = insert_pipeline_instance_by_name("vsm-wf-instance", 1, @now)
      si = insert_stage_instance(pi.id, "build", created_time: @now)
      insert_job_instance(si.id, "compile", @now, DateTime.add(@now, 120, :second))

      result = Analytics.vsm_workflow_trends("vsm-wf-instance", nil, 10)
      wf = hd(result.workflows)
      inst = hd(wf.instances)

      assert inst.pipeline_name == "vsm-wf-instance"
      assert inst.counter == 1
      assert inst.stages != []
      stage = hd(inst.stages)
      assert stage.name == "build"
      assert stage.result != nil
    end

    test "returns empty workflows for pipeline with no runs" do
      result = Analytics.vsm_workflow_trends("no-such-pipeline-vsm", nil, 10)
      assert result.pipelines == ["no-such-pipeline-vsm"]
      assert result.workflows == []
    end

    test "workflow start and end times are set correctly" do
      {pipeline, _, _} = insert_pipeline_with_jobs("vsm-wf-times", 1)

      t = @now
      pi = insert_pipeline_instance_by_name("vsm-wf-times", 1, t)
      si = insert_stage_instance(pi.id, "build", created_time: t)
      insert_job_instance(si.id, "compile", t, DateTime.add(t, 60, :second))

      result = Analytics.vsm_workflow_trends("vsm-wf-times", nil, 10)
      wf = hd(result.workflows)

      assert wf.start_time != nil
      assert wf.end_time != nil
      assert wf.total_duration_sec >= 0
    end

    test "workflows are sorted by counter descending (newest first)" do
      {pipeline, _, _} = insert_pipeline_with_jobs("vsm-wf-sorted", 1)

      t1 = @now
      t2 = DateTime.add(@now, 600, :second)

      pi1 = insert_pipeline_instance_by_name("vsm-wf-sorted", 1, t1)
      si1 = insert_stage_instance(pi1.id, "build", created_time: t1)
      insert_job_instance(si1.id, "compile", t1, DateTime.add(t1, 30, :second))

      pi2 = insert_pipeline_instance_by_name("vsm-wf-sorted", 2, t2)
      si2 = insert_stage_instance(pi2.id, "build", created_time: t2)
      insert_job_instance(si2.id, "compile", t2, DateTime.add(t2, 30, :second))

      result = Analytics.vsm_workflow_trends("vsm-wf-sorted", nil, 10)

      counters = Enum.map(result.workflows, & &1.source_counter)
      assert counters == [2, 1]
    end
  end

  describe "vsm_workflow_time_distribution/3" do
    test "returns nil when workflow not found" do
      result = Analytics.vsm_workflow_time_distribution("nonexistent", 999)
      assert is_nil(result)
    end

    test "returns stages for a specific workflow counter" do
      {_pipeline, _, _} = insert_pipeline_with_jobs("vsm-wfd-pipe", 1)

      pi = insert_pipeline_instance_by_name("vsm-wfd-pipe", 3, @now)
      si = insert_stage_instance(pi.id, "build", created_time: @now)
      insert_job_instance(si.id, "compile", @now, DateTime.add(@now, 90, :second))

      result = Analytics.vsm_workflow_time_distribution("vsm-wfd-pipe", 3)

      assert result != nil
      assert result.source_counter == 3
      assert result.pipelines == ["vsm-wfd-pipe"]
      assert result.stages != []
      stage = hd(result.stages)
      assert stage.pipeline_name == "vsm-wfd-pipe"
    end

    test "stages include build_time_sec and wait_time_sec" do
      {_pipeline, _, _} = insert_pipeline_with_jobs("vsm-wfd-times", 1)

      pi = insert_pipeline_instance_by_name("vsm-wfd-times", 1, @now)
      si = insert_stage_instance(pi.id, "test-stage", created_time: @now)
      insert_job_instance(si.id, "run", @now, DateTime.add(@now, 45, :second))

      result = Analytics.vsm_workflow_time_distribution("vsm-wfd-times", 1)

      assert result != nil
      stage = hd(result.stages)
      assert stage.build_time_sec != nil
      assert stage.wait_time_sec != nil
      assert stage.name == "test-stage"
    end
  end
end
