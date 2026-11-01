defmodule ExGoCD.AnalyticsPipelinesTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Analytics
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.JobInstance
  alias ExGoCD.Pipelines.PipelineInstance
  alias ExGoCD.Pipelines.StageInstance
  alias ExGoCD.Repo

  describe "pipeline_analytics/2" do
    test "a pipeline nobody has run has nothing to report" do
      {:ok, _pipeline} = Pipelines.create_pipeline(%{name: "never-ran", group: "test"})

      analytics = Analytics.pipeline_analytics("never-ran")

      assert analytics.run_count == 0
      assert analytics.pass_rate == nil
      assert analytics.recent_runs == []
    end

    test "reports how often the pipeline passed and how long a recovery takes" do
      {:ok, pipeline} = Pipelines.create_pipeline(%{name: "flaky", group: "test"})

      add_run(pipeline, counter: 1, result: "Failed")
      add_run(pipeline, counter: 2, result: "Passed", starts_seconds_later: 600)

      analytics = Analytics.pipeline_analytics("flaky")

      assert analytics.run_count == 2
      assert analytics.pass_rate == 50.0
      assert analytics.mttr_sec == 600.0
      assert Enum.map(analytics.recent_runs, & &1.status) == ["Passed", "Failed"]
      assert Enum.map(analytics.recent_runs, & &1.counter) == [2, 1]
    end

    test "reports how long a job waited for an agent" do
      {:ok, pipeline} = Pipelines.create_pipeline(%{name: "waits", group: "test"})

      add_run(pipeline, counter: 1, result: "Passed", waited_seconds: 90)

      assert Analytics.pipeline_analytics("waits").avg_wait_time_sec == 90.0
    end

    test "reports how long a run took from the start to the last completed stage" do
      {:ok, pipeline} = Pipelines.create_pipeline(%{name: "slow", group: "test"})

      add_run(pipeline, counter: 1, result: "Passed", build_seconds: 300)

      assert Analytics.pipeline_analytics("slow").avg_build_time_sec == 300.0
    end
  end

  # One pipeline instance with one stage and one job, which is what the
  # analytics read. `waited_seconds` is the time from the instance starting to
  # the job being picked up; `build_seconds` is the time to the stage finishing.
  defp add_run(pipeline, opts) do
    started_at = at(recent_start(), Keyword.get(opts, :starts_seconds_later))

    instance =
      Repo.insert!(%PipelineInstance{
        pipeline_id: pipeline.id,
        counter: Keyword.fetch!(opts, :counter),
        label: "#{Keyword.fetch!(opts, :counter)}",
        natural_order: Keyword.fetch!(opts, :counter) * 1.0,
        build_cause: %{},
        inserted_at: started_at,
        updated_at: started_at
      })

    stage =
      Repo.insert!(%StageInstance{
        pipeline_instance_id: instance.id,
        name: "build",
        counter: 1,
        order_id: 1,
        state: "Completed",
        result: Keyword.fetch!(opts, :result),
        inserted_at: started_at,
        updated_at: started_at,
        completed_at: at_usec(started_at, Keyword.get(opts, :build_seconds))
      })

    Repo.insert!(%JobInstance{
      stage_instance_id: stage.id,
      name: "compile",
      state: "Completed",
      result: Keyword.fetch!(opts, :result),
      scheduled_at: at_usec(started_at, nil),
      assigned_at: at_usec(started_at, Keyword.get(opts, :waited_seconds)),
      completed_at: at_usec(started_at, Keyword.get(opts, :build_seconds)),
      inserted_at: started_at,
      updated_at: started_at
    })

    instance
  end

  # The analytics window is the last 30 days, so the fixture starts an hour ago.
  defp recent_start do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-3600, :second)
  end

  defp at(time, nil), do: time
  defp at(time, seconds), do: DateTime.add(time, seconds, :second)

  # The job instance's timestamps are utc_datetime_usec, the others utc_datetime.
  defp at_usec(time, seconds), do: time |> at(seconds) |> DateTime.add(0, :microsecond)
end
