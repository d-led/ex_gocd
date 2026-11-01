defmodule ExGoCD.AnalyticsPipelinesTest do
  use ExGoCD.DataCase, async: true

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Analytics
  alias ExGoCD.Pipelines

  describe "pipeline_analytics/2" do
    test "a pipeline nobody has run has nothing to report" do
      {:ok, _pipeline} = Pipelines.create_pipeline(%{name: "never-ran", group: "test"})

      analytics = Analytics.pipeline_analytics("never-ran")

      assert analytics.run_count == 0
      assert analytics.pass_rate == nil
      assert analytics.recent_runs == []
    end

    test "reports how often the pipeline passed and how long a recovery takes" do
      {:ok, _pipeline} = Pipelines.create_pipeline(%{name: "flaky", group: "test"})

      failed_at = an_hour_ago()
      passed_at = DateTime.add(failed_at, 600, :second)

      add_run("flaky", counter: 1, started_at: failed_at, result: "Failed")
      add_run("flaky", counter: 2, started_at: passed_at, result: "Passed")

      analytics = Analytics.pipeline_analytics("flaky")

      assert analytics.run_count == 2
      assert analytics.pass_rate == 50.0
      assert analytics.mttr_sec == 600.0
      assert Enum.map(analytics.recent_runs, & &1.status) == ["Passed", "Failed"]
      assert Enum.map(analytics.recent_runs, & &1.counter) == [2, 1]
    end

    test "reports how long a job waited for an agent" do
      {:ok, _pipeline} = Pipelines.create_pipeline(%{name: "waits", group: "test"})

      add_run("waits", counter: 1, started_at: an_hour_ago(), waited_seconds: 90)

      assert Analytics.pipeline_analytics("waits").avg_wait_time_sec == 90.0
    end

    test "reports how long a run took from the start to the last completed stage" do
      {:ok, _pipeline} = Pipelines.create_pipeline(%{name: "slow", group: "test"})

      add_run("slow", counter: 1, started_at: an_hour_ago(), build_seconds: 300)

      assert Analytics.pipeline_analytics("slow").avg_build_time_sec == 300.0
    end
  end

  # The window these analytics read is the last 30 days, so the runs start an
  # hour ago rather than on a fixed date.
  defp an_hour_ago do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-3600, :second)
  end

  # One instance with one stage and one job: the wait is the gap between the
  # instance starting and the job being picked up, the build time the gap
  # between the instance starting and the stage completing.
  defp add_run(pipeline_name, opts) do
    started_at = Keyword.fetch!(opts, :started_at)
    picked_up_at = at(started_at, Keyword.get(opts, :waited_seconds, 0))
    completed_at = at(started_at, Keyword.get(opts, :build_seconds, 60))

    instance =
      insert_pipeline_instance_by_name(pipeline_name, Keyword.fetch!(opts, :counter), started_at)

    stage =
      insert_stage_instance(instance.id, "build",
        state: "Completed",
        result: Keyword.get(opts, :result, "Passed"),
        inserted_at: started_at,
        created_time: started_at,
        completed_at: usec(completed_at)
      )

    insert_job_instance(stage.id, "compile", usec(started_at), usec(picked_up_at))
  end

  defp at(time, seconds), do: DateTime.add(time, seconds, :second)

  # A job's timestamps are utc_datetime_usec; keeping the microseconds lets a
  # second-precision fixture be stored as one.
  defp usec(time), do: DateTime.add(time, 0, :microsecond)
end
