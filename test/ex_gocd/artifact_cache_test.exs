defmodule ExGoCD.ArtifactCacheTest do
  use ExUnit.Case, async: false

  alias ExGoCD.ArtifactCache

  @tmp_dir Path.join(System.tmp_dir!(), "artifact_cache_test")

  setup do
    File.mkdir_p!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  describe "cache put and get" do
    test "returns nil for uncached directory" do
      dir = Path.join(@tmp_dir, "uncached")
      File.mkdir_p!(dir)
      refute ArtifactCache.get(dir)
    end

    test "returns zip_path after put" do
      dir = Path.join(@tmp_dir, "stage1")
      File.mkdir_p!(dir)
      zip = Path.join(@tmp_dir, "stage1.zip")
      File.write!(zip, "fake zip content")

      ArtifactCache.put(dir, zip)
      assert ArtifactCache.get(dir) == zip
    end

    test "returns nil when cached zip file is deleted after put" do
      dir = Path.join(@tmp_dir, "deleted_stage")
      File.mkdir_p!(dir)
      zip = Path.join(@tmp_dir, "deleted.zip")
      File.write!(zip, "content")

      ArtifactCache.put(dir, zip)
      File.rm!(zip)

      refute ArtifactCache.get(dir)
    end
  end

  describe "stats" do
    test "reports zero after clear" do
      ArtifactCache.clear()
      stats = ArtifactCache.stats()
      assert stats.entry_count == 0
      assert stats.total_mb == 0.0
    end
  end
end
