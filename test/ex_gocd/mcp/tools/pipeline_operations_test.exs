defmodule ExGoCD.Mcp.Tools.PipelineOperationsTest do
  @moduledoc """
  The tools that change a pipeline: what they refuse, what they ask to be
  confirmed, and who they say did it.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.AuditLog
  alias ExGoCD.Mcp.Tools.PipelineOperations
  alias ExGoCD.Pipelines

  @ctx %{
    user: %ExGoCD.Accounts.User{username: "operator", roles: ["admin"], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  describe "gocd_set_pipeline_paused" do
    test "pausing records who asked and why, and writes the audit entry" do
      pipeline = insert_pipeline("freeze-me")

      assert {:ok, %{structured: %{"paused" => true}}} =
               PipelineOperations.call(
                 "gocd_set_pipeline_paused",
                 %{"name" => pipeline.name, "paused" => true, "cause" => "release window"},
                 @ctx
               )

      reloaded = Pipelines.get_pipeline_by_name("freeze-me")
      assert reloaded.paused_by == "operator"
      assert reloaded.pause_cause == "release window"

      assert [entry | _] = AuditLog.search(%{action: "pipeline.pause_toggled"})
      assert entry.actor == "operator"
      assert entry.resource_name == "freeze-me"
    end

    test "unpausing clears the cause" do
      pipeline = insert_pipeline("thaw-me")
      {:ok, _} = Pipelines.pause_pipeline(pipeline.name, "ops", "freezing")

      assert {:ok, _} =
               PipelineOperations.call(
                 "gocd_set_pipeline_paused",
                 %{"name" => pipeline.name, "paused" => false},
                 @ctx
               )

      refute Pipelines.get_pipeline_by_name("thaw-me").paused
    end
  end

  describe "gocd_trigger_pipeline" do
    test "a paused pipeline is refused with the reason, not an error to retry" do
      {pipeline, _stage, _jobs} = insert_pipeline_with_jobs("paused-trigger", 1)
      {:ok, _} = Pipelines.pause_pipeline(pipeline.name, "ops", "freezing")

      assert {:error, message} =
               PipelineOperations.call("gocd_trigger_pipeline", %{"name" => pipeline.name}, @ctx)

      assert message =~ "is paused"
    end

    test "a fingerprint the pipeline does not have is refused before anything is queued" do
      {pipeline, _stage, _job} = insert_pipeline_with_job_and_material("no-such-material")

      assert {:error, message} =
               PipelineOperations.call(
                 "gocd_trigger_pipeline",
                 %{
                   "name" => pipeline.name,
                   "materials" => [%{"fingerprint" => "not-a-fingerprint", "revision" => "abc"}]
                 },
                 @ctx
               )

      assert message =~ "not materials of"
    end

    test "a user without the trigger permission is told which permission they lack" do
      {pipeline, _stage, _jobs} = insert_pipeline_with_jobs("guarded", 1)

      {:ok, _} =
        ExGoCD.Accounts.create_user(%{
          username: "viewer",
          display_name: "V",
          roles: [],
          status: "Active"
        })

      viewer_ctx = %{
        @ctx
        | user: %ExGoCD.Accounts.User{username: "viewer", roles: [], status: "Active"}
      }

      assert {:error, message} =
               PipelineOperations.call(
                 "gocd_trigger_pipeline",
                 %{"name" => pipeline.name},
                 viewer_ctx
               )

      assert message =~ "trigger_pipeline"
    end
  end

  describe "gocd_unlock_pipeline" do
    test "asks for a confirmation before releasing a lock" do
      pipeline = locked_pipeline("locked-app")

      assert {:error, message} =
               PipelineOperations.call("gocd_unlock_pipeline", %{"name" => pipeline.name}, @ctx)

      assert message =~ "confirm: true"
      assert Pipelines.get_pipeline_by_name("locked-app").locked
    end

    test "releases the lock when confirmed" do
      pipeline = locked_pipeline("unlock-me")

      assert {:ok, %{structured: %{"changed" => true}}} =
               PipelineOperations.call(
                 "gocd_unlock_pipeline",
                 %{"name" => pipeline.name, "confirm" => true},
                 @ctx
               )

      refute Pipelines.get_pipeline_by_name("unlock-me").locked
    end

    test "says nothing changed for a pipeline that is not locked" do
      pipeline = insert_pipeline("never-locked")

      assert {:ok, %{structured: %{"changed" => false}}} =
               PipelineOperations.call("gocd_unlock_pipeline", %{"name" => pipeline.name}, @ctx)
    end
  end

  describe "gocd_comment_on_pipeline" do
    test "the comment is kept with the run and appears in the audit log" do
      insert_pipeline("commented")
      insert_pipeline_instance_by_name("commented", 1, DateTime.utc_now())

      assert {:ok, _} =
               PipelineOperations.call(
                 "gocd_comment_on_pipeline",
                 %{"name" => "commented", "counter" => 1, "comment" => "shipped by hand"},
                 @ctx
               )

      instance = Pipelines.get_pipeline_instance("commented", 1)
      assert instance.build_cause["comment"] == "shipped by hand"

      assert [entry | _] = AuditLog.search(%{action: "pipeline.commented"})
      assert entry.actor == "operator"
    end
  end

  # A lock only exists for a pipeline that can take one: `lock_behavior` is what
  # the server checks before it ever looks at the `locked` flag.
  defp locked_pipeline(name) do
    insert_pipeline(name, lock_behavior: "lockOnFailure")
    |> Ecto.Changeset.change(locked: true)
    |> ExGoCD.Repo.update!()
  end
end
