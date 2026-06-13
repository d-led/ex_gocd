defmodule ExGoCD.ArtifactCleanupTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.ArtifactCleanup
  alias ExGoCD.Pipelines.{Job, Pipeline, PipelineInstance, Stage, StageInstance}
  alias ExGoCD.Repo

  setup do
    # Ensure a clean test artifacts directory
    File.rm_rf!("test_artifacts")
    System.put_env("ARTIFACTS_DIR", "test_artifacts")

    on_exit(fn ->
      System.delete_env("ARTIFACTS_DIR")
      File.rm_rf!("test_artifacts")
    end)

    :ok
  end

  describe "directory size calculation" do
    test "correctly sums sizes of nested files" do
      File.mkdir_p!("test_artifacts/a/b")
      File.write!("test_artifacts/file1.txt", "12345") # 5 bytes
      File.write!("test_artifacts/a/file2.txt", "1234567890") # 10 bytes
      File.write!("test_artifacts/a/b/file3.txt", "12345") # 5 bytes

      assert ArtifactCleanup.get_dir_size("test_artifacts") == 20
    end
  end

  describe "artifact cleanup purging" do
    test "purges older runs but preserves the latest run and never_cleanup stages" do
      pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "clean-pipe", group: "test"}))

      stage_config = Repo.insert!(%Stage{} |> Stage.changeset(%{
        name: "build",
        pipeline_id: pipeline.id,
        approval_type: "success",
        never_cleanup_artifacts: false
      }))

      # 1. Insert 3 runs of this stage.
      # Run 1: Oldest
      pi1 = Repo.insert!(%PipelineInstance{} |> PipelineInstance.changeset(%{pipeline_id: pipeline.id, counter: 1, label: "1", natural_order: 1.0, build_cause: %{"triggerMessage" => "test"}}))
      si1 = insert_stage_instance(pi1.id, "build", 1, false, created_offset_seconds: -100, completed_offset_seconds: -90)

      # Run 2: Mid
      pi2 = Repo.insert!(%PipelineInstance{} |> PipelineInstance.changeset(%{pipeline_id: pipeline.id, counter: 2, label: "2", natural_order: 2.0, build_cause: %{"triggerMessage" => "test"}}))
      si2 = insert_stage_instance(pi2.id, "build", 1, false, created_offset_seconds: -50, completed_offset_seconds: -40)

      # Run 3: Latest (active run, latest_run: true)
      pi3 = Repo.insert!(%PipelineInstance{} |> PipelineInstance.changeset(%{pipeline_id: pipeline.id, counter: 3, label: "3", natural_order: 3.0, build_cause: %{"triggerMessage" => "test"}}))
      si3 = insert_stage_instance(pi3.id, "build", 1, true, created_offset_seconds: 0, completed_offset_seconds: 0)

      # Write dummy artifacts onto disk
      # Size of each: 100 bytes
      write_dummy_artifact("clean-pipe", 1, "build", 1, "data1.txt")
      write_dummy_artifact("clean-pipe", 2, "build", 1, "data2.txt")
      write_dummy_artifact("clean-pipe", 3, "build", 1, "data3.txt")

      # Total size: 300 bytes
      assert ArtifactCleanup.get_dir_size("test_artifacts") == 300

      # Set storage limit to 150 bytes (this requires freeing at least 150 bytes)
      # 150 bytes / (1024*1024) MB
      System.put_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB", "0.00015") # ~157 bytes

      # Run cleanup
      assert :ok = ArtifactCleanup.cleanup_if_needed()

      # Run 1 (oldest) should be deleted
      assert Repo.get!(StageInstance, si1.id).artifacts_deleted == true
      refute File.exists?("test_artifacts/clean-pipe/1/build/1/job/data1.txt")

      # Run 3 (latest) must NOT be deleted even though we need more space
      assert Repo.get!(StageInstance, si3.id).artifacts_deleted == false
      assert File.exists?("test_artifacts/clean-pipe/3/build/1/job/data3.txt")
    end

    test "respects never_cleanup_artifacts stage configuration" do
      pipeline = Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "no-clean-pipe", group: "test"}))

      stage_config = Repo.insert!(%Stage{} |> Stage.changeset(%{
        name: "build",
        pipeline_id: pipeline.id,
        approval_type: "success",
        never_cleanup_artifacts: true # NEVER CLEANUP
      }))

      pi1 = Repo.insert!(%PipelineInstance{} |> PipelineInstance.changeset(%{pipeline_id: pipeline.id, counter: 1, label: "1", natural_order: 1.0, build_cause: %{"triggerMessage" => "test"}}))
      si1 = insert_stage_instance(pi1.id, "build", 1, false, created_offset_seconds: -100, completed_offset_seconds: -90)

      write_dummy_artifact("no-clean-pipe", 1, "build", 1, "data.txt")

      System.put_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB", "0.00001") # very low

      # Run cleanup
      assert :ok = ArtifactCleanup.cleanup_if_needed()

      # Must not be deleted due to never_cleanup_artifacts: true config
      assert Repo.get!(StageInstance, si1.id).artifacts_deleted == false
      assert File.exists?("test_artifacts/no-clean-pipe/1/build/1/job/data.txt")
    end
  end

  defp insert_stage_instance(pipeline_instance_id, name, counter, latest_run, opts) do
    offset_created = Keyword.get(opts, :created_offset_seconds, 0)
    offset_completed = Keyword.get(opts, :completed_offset_seconds, 0)

    Repo.insert!(%StageInstance{} |> StageInstance.changeset(%{
      pipeline_instance_id: pipeline_instance_id,
      name: name,
      counter: counter,
      order_id: 1,
      state: "Completed",
      result: "Passed",
      approval_type: "success",
      created_time: DateTime.utc_now() |> DateTime.add(offset_created, :second),
      completed_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(offset_completed, :second),
      latest_run: latest_run,
      artifacts_deleted: false
    }))
  end

  defp write_dummy_artifact(pipeline, counter, stage, stage_counter, filename) do
    path = Path.join([
      "test_artifacts",
      pipeline,
      to_string(counter),
      stage,
      to_string(stage_counter),
      "job",
      filename
    ])
    File.mkdir_p!(Path.dirname(path))
    # Write exactly 100 bytes
    File.write!(path, String.duplicate("a", 100))
  end
end
