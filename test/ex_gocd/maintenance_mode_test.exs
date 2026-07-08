defmodule ExGoCD.MaintenanceModeTest do
  @moduledoc """
  Tests for MaintenanceMode GenServer — enable/disable pipeline scheduling pause.

  Covers ruby specs: MaintenanceModeDisableCreation.spec,
  StartServerInMaintenanceMode.spec

  Tests the GenServer directly via a locally-started process to avoid
  DistSingleton/Horde dependencies in test mode.
  """
  use ExGoCD.DataCase, async: false

  # Tests GenServer directly — Pipelines.trigger_pipeline calls
  # ExGoCD.MaintenanceMode.enabled?() which uses DistSingleton/Horde,
  # not available in test mode. GenServer state machine tested in isolation.

  setup do
    {:ok, pid} = GenServer.start_link(ExGoCD.MaintenanceMode, [], name: :mm_test)
    {:ok, pid: pid}
  end

  defp mm_call(msg), do: GenServer.call(:mm_test, msg)

  describe "initial state" do
    test "maintenance mode starts disabled" do
      refute mm_call(:enabled?)
    end

    test "info returns default state" do
      info = mm_call(:info)
      refute info.enabled
      assert info.enabled_at == nil
      assert info.enabled_by == nil
    end
  end

  describe "enable/disable lifecycle" do
    test "enable sets enabled to true" do
      assert {:ok, :enabled} = mm_call(:enable)
      assert mm_call(:enabled?)
    end

    test "disable sets enabled to false" do
      {:ok, :enabled} = mm_call(:enable)
      assert mm_call(:enabled?)
      assert {:ok, :disabled} = mm_call(:disable)
      refute mm_call(:enabled?)
    end

    test "enabling when already enabled returns error" do
      {:ok, :enabled} = mm_call(:enable)
      assert {:error, :already_enabled} = mm_call(:enable)
    end

    test "disabling when already disabled returns error" do
      assert {:error, :already_disabled} = mm_call(:disable)
    end

    test "info reflects current state after enable" do
      {:ok, :enabled} = mm_call(:enable)
      info = mm_call(:info)
      assert info.enabled
      assert info.enabled_at != nil
      assert info.enabled_by == "admin"
    end

    test "info reflects current state after disable" do
      {:ok, :enabled} = mm_call(:enable)
      {:ok, :disabled} = mm_call(:disable)
      info = mm_call(:info)
      refute info.enabled
      assert info.enabled_at == nil
      assert info.enabled_by == nil
    end
  end

  describe "state transitions are correct" do
    test "full enable/disable cycle works correctly" do
      {:ok, :enabled} = mm_call(:enable)
      assert mm_call(:enabled?)

      info = mm_call(:info)
      assert info.enabled
      assert info.enabled_at != nil
      assert info.enabled_by == "admin"

      {:ok, :disabled} = mm_call(:disable)
      refute mm_call(:enabled?)

      info2 = mm_call(:info)
      refute info2.enabled
      assert info2.enabled_at == nil
      assert info2.enabled_by == nil
    end
  end
end
