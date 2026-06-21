defmodule ExGoCD.AuditLogTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.AuditLog
  alias ExGoCD.AuditLog.Events

  setup do
    Events.pipeline_triggered("admin", "build-linux", 1)
    Events.pipeline_paused("admin", "build-linux", "admin")
    Events.pipeline_triggered("developer", "deploy-staging", 5)
    Events.admin_cleanup_stuck_jobs("admin", 3)
    :ok
  end

  describe "search/1" do
    test "returns all entries when no filters provided" do
      entries = AuditLog.search(%{})
      assert length(entries) == 4
    end

    test "filters by actor with case-insensitive partial match" do
      entries = AuditLog.search(%{actor: "admin"})
      assert length(entries) == 3
      assert Enum.all?(entries, &(&1.actor == "admin"))
    end

    test "filters by action with partial match" do
      entries = AuditLog.search(%{action: "trigger"})
      assert length(entries) == 2
      assert Enum.all?(entries, &String.contains?(&1.action, "trigger"))
    end

    test "filters by resource_name" do
      entries = AuditLog.search(%{resource_name: "deploy-staging"})
      assert length(entries) == 1
      assert hd(entries).resource_name == "deploy-staging"
    end

    test "combines multiple filters with AND logic" do
      entries = AuditLog.search(%{actor: "admin", action: "trigger"})
      assert length(entries) == 1
      entry = hd(entries)
      assert entry.actor == "admin"
      assert entry.action == "pipeline.triggered"
    end

    test "returns empty list when no entries match" do
      entries = AuditLog.search(%{actor: "nonexistent"})
      assert entries == []
    end

    test "filters by date_from" do
      tomorrow = Date.add(Date.utc_today(), 1)
      entries = AuditLog.search(%{date_from: tomorrow})
      assert entries == []
    end

    test "filters by date_to includes today's entries" do
      today = Date.utc_today()
      entries = AuditLog.search(%{date_to: today})
      # All seeded entries created today should be included
      assert length(entries) == 4
    end

    test "orders results newest first" do
      entries = AuditLog.search(%{})
      timestamps = Enum.map(entries, & &1.inserted_at)
      assert timestamps == Enum.sort(timestamps, {:desc, NaiveDateTime})
    end

    test "ignores empty string filters" do
      entries = AuditLog.search(%{actor: "", action: "trigger"})
      assert length(entries) == 2
    end
  end
end
