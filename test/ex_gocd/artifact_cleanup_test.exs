defmodule ExGoCD.ArtifactCleanupTest do
  use ExGoCD.DataCase, async: false

  # ExUnit creates a unique OS-temp sub-directory per test and removes it automatically.
  @moduletag :tmp_dir

  alias ExGoCD.ArtifactCleanup
  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance, Stage, StageInstance}
  alias ExGoCD.Repo

  setup %{tmp_dir: tmp_dir} do
    System.put_env("ARTIFACTS_DIR", tmp_dir)
    on_exit(fn -> System.delete_env("ARTIFACTS_DIR") end)
    {:ok, artifacts_dir: tmp_dir}
  end

  describe "directory size calculation" do
    test "correctly sums sizes of nested files", %{artifacts_dir: artifacts_dir} do
      File.mkdir_p!(Path.join([artifacts_dir, "a", "b"]))
      # 5 bytes
      File.write!(Path.join(artifacts_dir, "file1.txt"), "12345")
      # 10 bytes
      File.write!(Path.join([artifacts_dir, "a", "file2.txt"]), "1234567890")
      # 5 bytes
      File.write!(Path.join([artifacts_dir, "a", "b", "file3.txt"]), "12345")

      assert ArtifactCleanup.get_dir_size(artifacts_dir) == 20
    end
  end

  describe "artifact cleanup purging" do
    test "purges older runs but preserves the latest run and never_cleanup stages",
         %{artifacts_dir: artifacts_dir} do
      pipeline =
        Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "clean-pipe", group: "test"}))

      _stage_config =
        Repo.insert!(
          %Stage{}
          |> Stage.changeset(%{
            name: "build",
            pipeline_id: pipeline.id,
            approval_type: "success",
            never_cleanup_artifacts: false
          })
        )

      pi1 =
        Repo.insert!(
          %PipelineInstance{}
          |> PipelineInstance.changeset(%{
            pipeline_id: pipeline.id,
            counter: 1,
            label: "1",
            natural_order: 1.0,
            build_cause: %{"triggerMessage" => "test"}
          })
        )

      si1 =
        insert_stage_instance(pi1.id, "build", 1, false,
          created_offset_seconds: -100,
          completed_offset_seconds: -90
        )

      pi2 =
        Repo.insert!(
          %PipelineInstance{}
          |> PipelineInstance.changeset(%{
            pipeline_id: pipeline.id,
            counter: 2,
            label: "2",
            natural_order: 2.0,
            build_cause: %{"triggerMessage" => "test"}
          })
        )

      _si2 =
        insert_stage_instance(pi2.id, "build", 1, false,
          created_offset_seconds: -50,
          completed_offset_seconds: -40
        )

      pi3 =
        Repo.insert!(
          %PipelineInstance{}
          |> PipelineInstance.changeset(%{
            pipeline_id: pipeline.id,
            counter: 3,
            label: "3",
            natural_order: 3.0,
            build_cause: %{"triggerMessage" => "test"}
          })
        )

      si3 =
        insert_stage_instance(pi3.id, "build", 1, true,
          created_offset_seconds: 0,
          completed_offset_seconds: 0
        )

      write_dummy_artifact(artifacts_dir, "clean-pipe", 1, "build", 1, "data1.txt")
      write_dummy_artifact(artifacts_dir, "clean-pipe", 2, "build", 1, "data2.txt")
      write_dummy_artifact(artifacts_dir, "clean-pipe", 3, "build", 1, "data3.txt")

      assert ArtifactCleanup.get_dir_size(artifacts_dir) == 300

      # Threshold: ~157 bytes — forces cleanup of all but the latest run
      System.put_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB", "0.00015")

      assert :ok = ArtifactCleanup.cleanup_if_needed()

      assert Repo.get!(StageInstance, si1.id).artifacts_deleted == true

      refute File.exists?(
               Path.join([artifacts_dir, "clean-pipe", "1", "build", "1", "job", "data1.txt"])
             )

      assert Repo.get!(StageInstance, si3.id).artifacts_deleted == false

      assert File.exists?(
               Path.join([artifacts_dir, "clean-pipe", "3", "build", "1", "job", "data3.txt"])
             )
    end

    test "respects never_cleanup_artifacts stage configuration", %{artifacts_dir: artifacts_dir} do
      pipeline =
        Repo.insert!(%Pipeline{} |> Pipeline.changeset(%{name: "no-clean-pipe", group: "test"}))

      _stage_config =
        Repo.insert!(
          %Stage{}
          |> Stage.changeset(%{
            name: "build",
            pipeline_id: pipeline.id,
            approval_type: "success",
            never_cleanup_artifacts: true
          })
        )

      pi1 =
        Repo.insert!(
          %PipelineInstance{}
          |> PipelineInstance.changeset(%{
            pipeline_id: pipeline.id,
            counter: 1,
            label: "1",
            natural_order: 1.0,
            build_cause: %{"triggerMessage" => "test"}
          })
        )

      si1 =
        insert_stage_instance(pi1.id, "build", 1, false,
          created_offset_seconds: -100,
          completed_offset_seconds: -90
        )

      write_dummy_artifact(artifacts_dir, "no-clean-pipe", 1, "build", 1, "data.txt")

      System.put_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB", "0.00001")

      assert :ok = ArtifactCleanup.cleanup_if_needed()

      assert Repo.get!(StageInstance, si1.id).artifacts_deleted == false

      assert File.exists?(
               Path.join([artifacts_dir, "no-clean-pipe", "1", "build", "1", "job", "data.txt"])
             )
    end
  end

  defp insert_stage_instance(pipeline_instance_id, name, counter, latest_run, opts) do
    offset_created = Keyword.get(opts, :created_offset_seconds, 0)
    offset_completed = Keyword.get(opts, :completed_offset_seconds, 0)

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
        created_time: DateTime.utc_now() |> DateTime.add(offset_created, :second),
        completed_at: DateTime.utc_now() |> DateTime.add(offset_completed, :second),
        latest_run: latest_run,
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
