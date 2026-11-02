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

  # A name of its own per test: the registry is global, so a leftover process from
  # the previous test would otherwise answer this one's calls.
  setup do
    name = :"mm_test_#{System.unique_integer([:positive])}"

    start_supervised!(%{
      id: name,
      start: {GenServer, :start_link, [ExGoCD.MaintenanceMode, [], [name: name]]}
    })

    {:ok, mm: name}
  end

  defp mm_call(name, msg), do: GenServer.call(name, msg)

  describe "initial state" do
    test "maintenance mode starts disabled", %{mm: mm} do
      refute mm_call(mm, :enabled?)
    end

    test "info returns default state", %{mm: mm} do
      info = mm_call(mm, :info)
      refute info.enabled
      assert info.enabled_at == nil
      assert info.enabled_by == nil
    end
  end

  describe "enable/disable lifecycle" do
    test "enable sets enabled to true", %{mm: mm} do
      assert {:ok, :enabled} = mm_call(mm, :enable)
      assert mm_call(mm, :enabled?)
    end

    test "disable sets enabled to false", %{mm: mm} do
      {:ok, :enabled} = mm_call(mm, :enable)
      assert mm_call(mm, :enabled?)
      assert {:ok, :disabled} = mm_call(mm, :disable)
      refute mm_call(mm, :enabled?)
    end

    test "enabling when already enabled returns error", %{mm: mm} do
      {:ok, :enabled} = mm_call(mm, :enable)
      assert {:error, :already_enabled} = mm_call(mm, :enable)
    end

    test "disabling when already disabled returns error", %{mm: mm} do
      assert {:error, :already_disabled} = mm_call(mm, :disable)
    end

    test "info reflects current state after enable", %{mm: mm} do
      {:ok, :enabled} = mm_call(mm, :enable)
      info = mm_call(mm, :info)
      assert info.enabled
      assert info.enabled_at != nil
      assert info.enabled_by == "admin"
    end

    test "info reflects current state after disable", %{mm: mm} do
      {:ok, :enabled} = mm_call(mm, :enable)
      {:ok, :disabled} = mm_call(mm, :disable)
      info = mm_call(mm, :info)
      refute info.enabled
      assert info.enabled_at == nil
      assert info.enabled_by == nil
    end
  end

  describe "state transitions are correct" do
    test "full enable/disable cycle works correctly", %{mm: mm} do
      {:ok, :enabled} = mm_call(mm, :enable)
      assert mm_call(mm, :enabled?)

      info = mm_call(mm, :info)
      assert info.enabled
      assert info.enabled_at != nil
      assert info.enabled_by == "admin"

      {:ok, :disabled} = mm_call(mm, :disable)
      refute mm_call(mm, :enabled?)

      info2 = mm_call(mm, :info)
      refute info2.enabled
      assert info2.enabled_at == nil
      assert info2.enabled_by == nil
    end
  end
end
