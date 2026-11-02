defmodule ExGoCD.StageNotificationsTest do
  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures
  import Swoosh.TestAssertions

  alias ExGoCD.Accounts
  alias ExGoCD.Notifications
  alias ExGoCD.Pipelines

  @now ~U[2026-10-01 09:00:00.000000Z]

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        username: "notified-#{System.unique_integer([:positive])}",
        display_name: "Notified"
      })

    %{user: user}
  end

  describe "a stage that fails" do
    test "emails the person who asked to hear about failures", %{user: user} do
      filter(user, "fails")

      complete_only_job("notify-fail", "Failed")

      assert_email_sent(fn email -> email.to == [{"", user.username}] end)
    end

    test "does not email the person who asked to hear about passes", %{user: user} do
      filter(user, "passes")

      complete_only_job("notify-not-pass", "Failed")

      refute_email_sent()
    end
  end

  describe "a stage that is cancelled" do
    test "emails the person who asked to hear about cancellations", %{user: user} do
      filter(user, "cancelled")

      {pipeline_name, pipeline_counter, stage_name} = pipeline_awaiting_a_stage()
      {:ok, _stage} = Pipelines.cancel_stage(pipeline_name, pipeline_counter, stage_name)

      assert_email_sent(fn email -> email.to == [{"", user.username}] end)
    end
  end

  defp filter(user, event) do
    {:ok, filter} =
      Notifications.create_filter(%{
        user_id: user.id,
        pipeline_name: "notify-fail",
        stage_name: "build",
        event: event
      })

    filter
  end

  # A pipeline whose single stage has one job, completed with `result`, which is
  # what makes the stage complete.
  defp complete_only_job(pipeline_name, result) do
    {_pipeline, stage, [job]} = insert_pipeline_with_jobs(pipeline_name, 1)
    instance = insert_pipeline_instance_by_name(pipeline_name, 1, @now)
    stage_instance = insert_stage_instance(instance.id, stage.name, created_time: @now)
    job_instance = insert_job_instance(stage_instance.id, job.name, @now, @now)

    Pipelines.complete_job_instance(job_instance.id, result)
  end

  defp pipeline_awaiting_a_stage do
    pipeline_name = "notify-fail"
    {_pipeline, stage, [job]} = insert_pipeline_with_jobs(pipeline_name, 1)
    instance = insert_pipeline_instance_by_name(pipeline_name, 1, @now)
    stage_instance = insert_stage_instance(instance.id, stage.name, created_time: @now)
    insert_job_instance(stage_instance.id, job.name, @now, @now)

    {pipeline_name, instance.counter, stage_instance.name}
  end
end
