defmodule ExGoCD.SchedulingChecker.DiskSpaceTest do
  @moduledoc """
  Tests for the disk space checker.
  Behaviour-driven: given the DiskSpace monitor status,
  critical status blocks scheduling, ok/warning allow it,
  and missing GenServer defaults to :ok.
  """
  use ExUnit.Case, async: true

  alias ExGoCD.SchedulingChecker.DiskSpace

  describe "check/1" do
    test "returns :ok when DiskSpace monitor is not running (default safe)" do
      # In test env, DiskSpace GenServer is not started
      assert DiskSpace.check("any-pipeline") == :ok
    end

    test "accepts any pipeline name (pipeline-agnostic)" do
      assert DiskSpace.check("pipe-a") == :ok
      assert DiskSpace.check("pipe-b") == :ok
      assert DiskSpace.check("") == :ok
    end
  end
end
