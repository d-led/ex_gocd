defmodule ExGoCD.StageStatusTest do
  use ExUnit.Case, async: true

  alias ExGoCD.StageStatus

  describe "pipeline_status/1" do
    test "empty stages → Not Yet Run" do
      assert StageStatus.pipeline_status([]) == "Not Yet Run"
    end

    test "all Passed → Passed" do
      assert StageStatus.pipeline_status(["Passed", "Passed"]) == "Passed"
    end

    test "mixed Passed+Completed → Passed" do
      assert StageStatus.pipeline_status(["Passed", "Completed"]) == "Passed"
    end

    test "any Failed dominates → Failed" do
      assert StageStatus.pipeline_status(["Passed", "Failed", "Passed"]) == "Failed"
    end

    test "any Building dominates → Building" do
      assert StageStatus.pipeline_status(["Passed", "Building"]) == "Building"
    end

    test "any Cancelled dominates → Cancelled" do
      assert StageStatus.pipeline_status(["Passed", "Cancelled"]) == "Cancelled"
    end

    test "Awaiting shows when no worse status" do
      assert StageStatus.pipeline_status(["Awaiting"]) == "Awaiting"
    end

    test "all Not Yet Run → Not Yet Run" do
      assert StageStatus.pipeline_status(["Not Yet Run", "Not Yet Run"]) == "Not Yet Run"
    end

    test "unknown status → Unknown (catch bugs)" do
      assert StageStatus.pipeline_status(["SomeWeirdStatus"]) == "Unknown"
    end
  end

  describe "from_instance/1" do
    test "uses result when set" do
      assert StageStatus.from_instance(%{result: "Passed", state: "Completed"}) == "Passed"
    end

    test "falls back to state when result is Unknown" do
      assert StageStatus.from_instance(%{result: "Unknown", state: "Completed"}) == "Completed"
    end

    test "uses state when result is nil" do
      assert StageStatus.from_instance(%{state: "Building"}) == "Building"
    end
  end

  # Note: stage_bg/1, node_border/1, and node_badge/1 are presentation helpers
  # that map domain statuses to CSS classes. They live here for co-location with
  # the status constants but are tested implicitly through VSM LiveView tests —
  # asserting on specific CSS class strings is testing implementation, not behavior.
end
