defmodule ExGoCD.Monitors.DiskSpaceTest do
  # The monitor reads the server's stored artifacts directory — a database read
  # made by a shared process — so this runs in the shared sandbox, not async.
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Monitors.DiskSpace
  alias ExGoCD.SchedulingChecker
  alias ExGoCD.ServerConfig

  @moduletag :tmp_dir

  test "measures the directory artifacts are stored in", %{tmp_dir: tmp_dir} do
    {:ok, _} = ServerConfig.update(%{"artifacts_dir" => tmp_dir})

    assert DiskSpace.check_now() in [:ok, :warning, :critical]
  end

  test "says the disk is unknown when the directory cannot be read", %{tmp_dir: tmp_dir} do
    {:ok, _} = ServerConfig.update(%{"artifacts_dir" => Path.join(tmp_dir, "gone")})

    assert DiskSpace.check_now() == :unknown
  end

  test "does not block scheduling on a disk it could not measure", %{tmp_dir: tmp_dir} do
    {:ok, _} = ServerConfig.update(%{"artifacts_dir" => Path.join(tmp_dir, "gone")})
    :unknown = DiskSpace.check_now()

    assert SchedulingChecker.DiskSpace.check("any-pipeline") == :ok
  end
end
