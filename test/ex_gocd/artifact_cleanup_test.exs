defmodule ExGoCD.ArtifactCleanupTest do
  use ExGoCD.DataCase, async: false

  @moduletag :tmp_dir

  alias ExGoCD.ArtifactCleanup
  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance, Stage, StageInstance}
  alias ExGoCD.Repo

  setup %{tmp_dir: tmp_dir} do
    System.put_env("ARTIFACTS_DIR", tmp_dir)
    # Ensure defaults for isolation
    System.delete_env("EX_GOCD_ARTIFACT_CLEANUP_ENABLED")
    System.delete_env("EX_GOCD_MAX_ARTIFACT_AGE_DAYS")

    on_exit(fn ->
      System.delete_env("ARTIFACTS_DIR")
      System.delete_env("EX_GOCD_ARTIFACT_CLEANUP_ENABLED")
      System.delete_env("EX_GOCD_MAX_ARTIFACT_AGE_DAYS")
      System.delete_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB")
    end)

    {:ok, artifacts_dir: tmp_dir}
  end

  describe "directory size calculation" do
    test "correctly sums sizes of nested files", %{artifacts_dir: artifacts_dir} do
      File.mkdir_p!(Path.join([artifacts_dir, "a", "b"]))
      File.write!(Path.join(artifacts_dir, "file1.txt"), "12345")
      File.write!(Path.join([artifacts_dir, "a", "file2.txt"]), "1234567890")
      File.write!(Path.join([artifacts_dir, "a", "b", "file3.txt"]), "12345")

      assert ArtifactCleanup.get_dir_size(artifacts_dir) == 20
    end
  end

  describe "size-based cleanup with retention_runs = 1" do
    test "purges older runs but keeps the latest (N=1 default)",
         %{artifacts_dir: artifacts_dir} do
      pipeline =
        Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "ret-1-pipe", group: "test"}))

      _stage =
        Repo.insert!(
          %Stage{}
          |> Stage.changeset(%{
            name: "build",
            pipeline_id: pipeline.id,
            approval_type: "success",
            artifact_retention_runs: 1
          })
        )

      pi1 = insert_pipeline_instance(pipeline.id, 1)
      si1 = insert_stage_instance(pi1.id, "build", 1, -100, -90)

      pi2 = insert_pipeline_instance(pipeline.id, 2)
      _si2 = insert_stage_instance(pi2.id, "build", 1, -50, -40)

      pi3 = insert_pipeline_instance(pipeline.id, 3)
      si3 = insert_stage_instance(pi3.id, "build", 1, 0, 0)

      write_dummy_artifact(artifacts_dir, "ret-1-pipe", 1, "build", 1, "data1.txt")
      write_dummy_artifact(artifacts_dir, "ret-1-pipe", 2, "build", 1, "data2.txt")
      write_dummy_artifact(artifacts_dir, "ret-1-pipe", 3, "build", 1, "data3.txt")

      assert ArtifactCleanup.get_dir_size(artifacts_dir) == 300

      System.put_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB", "0.00015")
      assert :ok = ArtifactCleanup.cleanup_if_needed()

      # counter 1 purged
      assert Repo.get!(StageInstance, si1.id).artifacts_deleted == true
      refute File.exists?(
               Path.join([artifacts_dir, "ret-1-pipe", "1", "build", "1", "job", "data1.txt"])
             )

      # counter 3 (latest) kept
      assert Repo.get!(StageInstance, si3.id).artifacts_deleted == false
      assert File.exists?(
               Path.join([artifacts_dir, "ret-1-pipe", "3", "build", "1", "job", "data3.txt"])
             )
    end
  end

  describe "per-stage retention: keep last N runs" do
    test "keeps last 2 runs when artifact_retention_runs = 2",
         %{artifacts_dir: artifacts_dir} do
      pipeline =
        Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "ret-2-pipe", group: "test"}))

      _stage =
        Repo.insert!(
          %Stage{}
          |> Stage.changeset(%{
            name: "build",
            pipeline_id: pipeline.id,
            approval_type: "success",
            artifact_retention_runs: 2
          })
        )

      pi1 = insert_pipeline_instance(pipeline.id, 1)
      si1 = insert_stage_instance(pi1.id, "build", 1, -200, -190)

      pi2 = insert_pipeline_instance(pipeline.id, 2)
      si2 = insert_stage_instance(pi2.id, "build", 1, -100, -90)

      pi3 = insert_pipeline_instance(pipeline.id, 3)
      si3 = insert_stage_instance(pi3.id, "build", 1, 0, 0)

      write_dummy_artifact(artifacts_dir, "ret-2-pipe", 1, "build", 1, "data1.txt")
      write_dummy_artifact(artifacts_dir, "ret-2-pipe", 2, "build", 1, "data2.txt")
      write_dummy_artifact(artifacts_dir, "ret-2-pipe", 3, "build", 1, "data3.txt")

      System.put_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB", "0.00015")
      assert :ok = ArtifactCleanup.cleanup_if_needed()

      # counter 1 purged (outside retention window of 2)
      assert Repo.get!(StageInstance, si1.id).artifacts_deleted == true
      refute File.exists?(
               Path.join([artifacts_dir, "ret-2-pipe", "1", "build", "1", "job", "data1.txt"])
             )

      # counter 2 and 3 kept (within last 2)
      assert Repo.get!(StageInstance, si2.id).artifacts_deleted == false
      assert File.exists?(
               Path.join([artifacts_dir, "ret-2-pipe", "2", "build", "1", "job", "data2.txt"])
             )

      assert Repo.get!(StageInstance, si3.id).artifacts_deleted == false
      assert File.exists?(
               Path.join([artifacts_dir, "ret-2-pipe", "3", "build", "1", "job", "data3.txt"])
             )
    end

    test "deletes all when artifact_retention_runs = 0 (except never_cleanup)",
         %{artifacts_dir: artifacts_dir} do
      pipeline =
        Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "ret-0-pipe", group: "test"}))

      _stage =
        Repo.insert!(
          %Stage{}
          |> Stage.changeset(%{
            name: "build",
            pipeline_id: pipeline.id,
            approval_type: "success",
            artifact_retention_runs: 0
          })
        )

      pi1 = insert_pipeline_instance(pipeline.id, 1)
      si1 = insert_stage_instance(pi1.id, "build", 1, -100, -90)

      pi2 = insert_pipeline_instance(pipeline.id, 2)
      si2 = insert_stage_instance(pi2.id, "build", 1, 0, 0)

      write_dummy_artifact(artifacts_dir, "ret-0-pipe", 1, "build", 1, "data1.txt")
      write_dummy_artifact(artifacts_dir, "ret-0-pipe", 2, "build", 1, "data2.txt")

      System.put_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB", "0.00001")
      assert :ok = ArtifactCleanup.cleanup_if_needed()

      # Both purged — retention=0 means keep none
      assert Repo.get!(StageInstance, si1.id).artifacts_deleted == true
      assert Repo.get!(StageInstance, si2.id).artifacts_deleted == true
      refute File.exists?(
               Path.join([artifacts_dir, "ret-0-pipe", "2", "build", "1", "job", "data2.txt"])
             )
    end
  end

  describe "never_cleanup_artifacts" do
    test "never_cleanup_artifacts overrides retention_runs", %{artifacts_dir: artifacts_dir} do
      pipeline =
        Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "never-pipe", group: "test"}))

      _stage =
        Repo.insert!(
          %Stage{}
          |> Stage.changeset(%{
            name: "build",
            pipeline_id: pipeline.id,
            approval_type: "success",
            never_cleanup_artifacts: true,
            artifact_retention_runs: 0
          })
        )

      pi1 = insert_pipeline_instance(pipeline.id, 1)
      si1 = insert_stage_instance(pi1.id, "build", 1, -100, -90)

      write_dummy_artifact(artifacts_dir, "never-pipe", 1, "build", 1, "data.txt")

      System.put_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB", "0.00001")
      assert :ok = ArtifactCleanup.cleanup_if_needed()

      # Protected by never_cleanup_artifacts — even with retention_runs=0
      assert Repo.get!(StageInstance, si1.id).artifacts_deleted == false
      assert File.exists?(
               Path.join([artifacts_dir, "never-pipe", "1", "build", "1", "job", "data.txt"])
             )
    end
  end

  describe "age-based purge" do
    test "deletes artifacts older than EX_GOCD_MAX_ARTIFACT_AGE_DAYS",
         %{artifacts_dir: artifacts_dir} do
      pipeline =
        Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "age-pipe", group: "test"}))

      _stage =
        Repo.insert!(
          %Stage{}
          |> Stage.changeset(%{
            name: "build",
            pipeline_id: pipeline.id,
            approval_type: "success",
            artifact_retention_runs: 1
          })
        )

      pi1 = insert_pipeline_instance(pipeline.id, 1)
      si1 = insert_stage_instance(pi1.id, "build", 1, -200, -190)

      pi2 = insert_pipeline_instance(pipeline.id, 2)
      si2 = insert_stage_instance(pi2.id, "build", 1, 0, 0)

      write_dummy_artifact(artifacts_dir, "age-pipe", 1, "build", 1, "old.txt")
      write_dummy_artifact(artifacts_dir, "age-pipe", 2, "build", 1, "new.txt")

      # Age limit: 0.0001 days (~8.6 seconds) — si1 completed 190s ago → should be purged
      System.put_env("EX_GOCD_MAX_ARTIFACT_AGE_DAYS", "0.0001")

      assert :ok = ArtifactCleanup.cleanup_if_needed()

      # si1 is older than age cutoff → purged
      assert Repo.get!(StageInstance, si1.id).artifacts_deleted == true
      refute File.exists?(
               Path.join([artifacts_dir, "age-pipe", "1", "build", "1", "job", "old.txt"])
             )

      # si2 is recent → kept
      assert Repo.get!(StageInstance, si2.id).artifacts_deleted == false
      assert File.exists?(
               Path.join([artifacts_dir, "age-pipe", "2", "build", "1", "job", "new.txt"])
             )
    end
  end

  describe "global toggle" do
    test "cleanup is skipped when EX_GOCD_ARTIFACT_CLEANUP_ENABLED=false",
         %{artifacts_dir: artifacts_dir} do
      pipeline =
        Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "tog-pipe", group: "test"}))

      _stage =
        Repo.insert!(
          %Stage{}
          |> Stage.changeset(%{
            name: "build",
            pipeline_id: pipeline.id,
            approval_type: "success",
            artifact_retention_runs: 0
          })
        )

      pi1 = insert_pipeline_instance(pipeline.id, 1)
      si1 = insert_stage_instance(pi1.id, "build", 1, -100, -90)

      write_dummy_artifact(artifacts_dir, "tog-pipe", 1, "build", 1, "data.txt")

      System.put_env("EX_GOCD_ARTIFACT_CLEANUP_ENABLED", "false")
      System.put_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB", "0.00001")

      assert :ok = ArtifactCleanup.cleanup_if_needed()

      # Nothing deleted — cleanup disabled globally
      assert Repo.get!(StageInstance, si1.id).artifacts_deleted == false
      assert File.exists?(
               Path.join([artifacts_dir, "tog-pipe", "1", "build", "1", "job", "data.txt"])
             )
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════════════

  defp insert_pipeline_instance(pipeline_id, counter) do
    Repo.insert!(
      %PipelineInstance{}
      |> PipelineInstance.changeset(%{
        pipeline_id: pipeline_id,
        counter: counter,
        label: to_string(counter),
        natural_order: counter * 1.0,
        build_cause: %{"triggerMessage" => "test"}
      })
    )
  end

  defp insert_stage_instance(pipeline_instance_id, name, counter, created_offset, completed_offset) do
    now = DateTime.utc_now()

    Repo.insert!(
      %StageInstance{}
      |> StageInstance.changeset(%{
        pipeline_instance_id: pipeline_instance_id,
        name: name,
        counter: counter,
        order_id: 1,
        state: "Completed",
        result: "Passed",
        approval_type: "success",
        created_time: DateTime.add(now, created_offset, :second),
        completed_at: DateTime.add(now, completed_offset, :second),
        latest_run: false,
        artifacts_deleted: false
      })
    )
  end

  defp write_dummy_artifact(artifacts_dir, pipeline, counter, stage, stage_counter, filename) do
    path =
      Path.join([
        artifacts_dir,
        pipeline,
        to_string(counter),
        stage,
        to_string(stage_counter),
        "job",
        filename
      ])

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, String.duplicate("a", 100))
  end
end
