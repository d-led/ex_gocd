defmodule ExGoCD.AuditLog.EventsTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.AuditLog
  alias ExGoCD.AuditLog.Events

  describe "pipeline events" do
    test "pipeline_triggered/3 stores event with versioned payload" do
      Events.pipeline_triggered("admin", "my-pipeline", 42)

      [entry] = AuditLog.recent(1)
      assert entry.actor == "admin"
      assert entry.action == "pipeline.triggered"
      assert entry.resource_type == "pipeline"
      assert entry.resource_name == "my-pipeline"

      assert %{"event_version" => 1, "payload" => %{"counter" => 42}} = entry.details
    end

    test "pipeline_paused/3 stores event with paused_by in payload" do
      Events.pipeline_paused("admin", "my-pipeline", "operator")

      [entry] = AuditLog.recent(1)
      assert entry.action == "pipeline.paused"
      assert entry.resource_name == "my-pipeline"
      assert %{"event_version" => 1, "payload" => %{"paused_by" => "operator"}} = entry.details
    end

    test "pipeline_pause_toggled/3 stores event with paused flag" do
      Events.pipeline_pause_toggled("admin", "my-pipeline", true)

      [entry] = AuditLog.recent(1)
      assert entry.action == "pipeline.pause_toggled"
      assert %{"event_version" => 1, "payload" => %{"paused" => true}} = entry.details
    end
  end

  describe "admin events" do
    test "admin_cleanup_stuck_jobs/2 stores event with count" do
      Events.admin_cleanup_stuck_jobs("admin", 7)

      [entry] = AuditLog.recent(1)
      assert entry.action == "admin.cleanup_stuck_jobs"
      assert entry.resource_type == nil
      assert %{"event_version" => 1, "payload" => %{"count" => 7}} = entry.details
    end

    test "admin_reset_pipeline/2 stores event with pipeline_name in payload" do
      Events.admin_reset_pipeline("admin", "my-pipeline")

      [entry] = AuditLog.recent(1)
      assert entry.action == "admin.reset_pipeline"
      assert entry.resource_type == "pipeline"
      assert entry.resource_name == "my-pipeline"

      assert %{"event_version" => 1, "payload" => %{"pipeline_name" => "my-pipeline"}} =
               entry.details
    end
  end
end
