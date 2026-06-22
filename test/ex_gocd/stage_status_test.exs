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

  describe "stage_bg/1" do
    test "returns a CSS class for known statuses" do
      assert is_binary(StageStatus.stage_bg("Passed"))
      assert is_binary(StageStatus.stage_bg("Failed"))
      assert is_binary(StageStatus.stage_bg("Building"))
      assert is_binary(StageStatus.stage_bg("Not Yet Run"))
    end

    test "returns gray fallback for unknown" do
      assert StageStatus.stage_bg("bogus") == "bg-gray-300"
    end
  end

  describe "node_border/1" do
    test "returns cyan border for nil (un-triggered)" do
      assert StageStatus.node_border(nil) == "border-[#2fa8b6]"
    end

    test "returns green border for Passed" do
      assert StageStatus.node_border("Passed") =~ "5cb85c"
    end
  end
end
