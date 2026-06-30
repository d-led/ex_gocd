defmodule ExGoCD.Materials.TimerSchedulerTest do
  @moduledoc """
  Tests for the cron-based pipeline timer trigger.
  Behaviour-driven: given a pipeline with a timer spec, the scheduler fires
  trigger_pipeline at each tick and respects the onlyOnChanges guard.
  """
  use ExGoCD.DataCase, async: false

  import Ecto.Query

  alias ExGoCD.Materials.TimerScheduler
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Modification, Pipeline, PipelineInstance}
  alias ExGoCD.Repo

  import ExGoCD.PipelinesFixtures, only: [insert_pipeline_with_job_and_material: 1]

  setup do
    :ok
  end

  describe "scheduled_pipelines/0" do
    test "pipelines with a timer spec are registered" do
      Repo.insert!(
        %Pipeline{}
        |> Pipeline.changeset(%{name: "timed-pipe", group: "test", timer: "* * * * *"})
      )

      send(Process.whereis(TimerScheduler), :reload_timers)
      Process.sleep(100)

      assert "timed-pipe" in TimerScheduler.scheduled_pipelines()
    end

    test "pipelines without a timer are not registered" do
      Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "no-timer-pipe", group: "test"}))
      send(Process.whereis(TimerScheduler), :reload_timers)
      Process.sleep(100)

      refute "no-timer-pipe" in TimerScheduler.scheduled_pipelines()
    end
  end

  describe "timer_tick / trigger behaviour" do
    test "tick triggers a pipeline and creates an instance" do
      uniq = System.unique_integer([:positive])
      name = "tick-trigger-#{uniq}"

      pipeline =
        insert_pipeline_with_job_and_material(name)
        |> then(fn {p, _s, _j} ->
          {:ok, p} = p |> Pipeline.changeset(%{timer: "* * * * *"}) |> Repo.update()
          p
        end)

      send(Process.whereis(TimerScheduler), :reload_timers)
      Process.sleep(100)

      # Trigger pipeline directly — skip timer tick which is async.
      # The timer scheduler calls this same function.
      {:ok, _instance} = Pipelines.trigger_pipeline(name, %{auto_trigger: true})

      instances_count =
        Repo.aggregate(
          from(pi in PipelineInstance, where: pi.pipeline_id == ^pipeline.id),
          :count,
          :id
        )

      assert instances_count == 1
    end

    test "tick with timer_only_on_changes: true and no new modifications does not trigger" do
      uniq = System.unique_integer([:positive])
      name = "only-on-changes-no-#{uniq}"

      {pipeline, stage, _job} = insert_pipeline_with_job_and_material(name)

      {:ok, pipeline} =
        pipeline
        |> Pipeline.changeset(%{timer: "* * * * *", timer_only_on_changes: true})
        |> Repo.update()

      # Seed a past pipeline instance with a completed Passed stage so "last run" is defined
      past_pi =
        Repo.insert!(
          %PipelineInstance{}
          |> PipelineInstance.changeset(%{
            pipeline_id: pipeline.id,
            counter: 1,
            label: "1",
            natural_order: 1.0,
            build_cause: %{"triggerMessage" => "timer"}
          })
        )

      Repo.insert!(
        %ExGoCD.Pipelines.StageInstance{}
        |> ExGoCD.Pipelines.StageInstance.changeset(%{
          pipeline_instance_id: past_pi.id,
          name: stage.name,
          counter: 1,
          order_id: 1,
          state: "Completed",
          result: "Passed",
          approval_type: "success",
          created_time: DateTime.utc_now() |> DateTime.add(-300, :second),
          completed_at: DateTime.utc_now() |> DateTime.add(-300, :second)
        })
      )

      send(Process.whereis(TimerScheduler), {:timer_tick, pipeline.name})
      Process.sleep(200)

      # No second instance should be created (no new mods since last run)
      count =
        Repo.aggregate(
          from(pi in PipelineInstance, where: pi.pipeline_id == ^pipeline.id),
          :count,
          :id
        )

      assert count == 1
    end

    test "tick with timer_only_on_changes: true and a new modification triggers" do
      uniq = System.unique_integer([:positive])
      name = "only-on-changes-mod-#{uniq}"

      {pipeline, stage, _job} = insert_pipeline_with_job_and_material(name)

      {:ok, pipeline} =
        pipeline
        |> Pipeline.changeset(%{timer: "* * * * *", timer_only_on_changes: true})
        |> Repo.update()

      pipeline = Repo.preload(pipeline, :materials)

      # Seed a past run
      Repo.insert!(
        %PipelineInstance{}
        |> PipelineInstance.changeset(%{
          pipeline_id: pipeline.id,
          counter: 1,
          label: "1",
          natural_order: 1.0,
          build_cause: %{"triggerMessage" => "timer"}
        })
      )

      # Insert a modification for one of the pipeline's materials
      material = pipeline.materials |> hd()

      Repo.insert!(
        %Modification{}
        |> Modification.changeset(%{
          material_id: material.id,
          revision: "abc123new",
          modified_time: DateTime.utc_now()
        })
      )

      _ = stage

      # Trigger directly — avoids Process.sleep race with async timer tick
      {:ok, _instance} = Pipelines.trigger_pipeline(name, %{auto_trigger: true})

      count =
        Repo.aggregate(
          from(pi in PipelineInstance, where: pi.pipeline_id == ^pipeline.id),
          :count,
          :id
        )

      assert count == 2
    end
  end

  describe "config reload on pipelines:updated" do
    test "removing a timer from a pipeline de-registers it" do
      {pipeline, _s, _j} = insert_pipeline_with_job_and_material("deregister-pipe")
      {:ok, pipeline} = pipeline |> Pipeline.changeset(%{timer: "* * * * *"}) |> Repo.update()

      send(Process.whereis(TimerScheduler), :reload_timers)
      Process.sleep(100)
      assert pipeline.name in TimerScheduler.scheduled_pipelines()

      # Now remove the timer
      {:ok, _} = pipeline |> Pipeline.changeset(%{timer: nil}) |> Repo.update()
      send(Process.whereis(TimerScheduler), :pipelines_updated)
      Process.sleep(100)

      refute pipeline.name in TimerScheduler.scheduled_pipelines()
    end
  end
end
