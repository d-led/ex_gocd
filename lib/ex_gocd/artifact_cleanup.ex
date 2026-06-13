# Copyright 2026 ex_gocd
# Module to clean up artifacts when storage limit is exceeded.

defmodule ExGoCD.ArtifactCleanup do
  @moduledoc """
  Manages artifact storage limits by purging old stage artifacts.
  Always keeps the artifacts of the latest run of any job/stage.
  """
  import Ecto.Query
  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance, StageInstance}
  alias ExGoCD.Repo

  require Logger

  @default_max_size_mb 500

  @doc """
  Runs the cleanup check and purges old artifacts if the limit is exceeded.
  """
  def cleanup_if_needed do
    limit_mb = get_limit_mb()
    artifacts_path = artifacts_dir()

    if File.exists?(artifacts_path) do
      current_size = get_dir_size(artifacts_path)
      limit_bytes = limit_mb * 1024 * 1024

      if current_size > limit_bytes do
        Logger.info("Artifacts directory size (#{current_size} bytes) exceeds limit (#{limit_bytes} bytes). Starting cleanup...")
        purge_old_artifacts(current_size - limit_bytes)
        :ok
      else
        :ok
      end
    else
      :ok
    end
  end

  defp get_limit_mb do
    case System.get_env("EX_GOCD_MAX_ARTIFACTS_SIZE_MB") do
      nil -> Application.get_env(:ex_gocd, :max_artifact_storage_mb, @default_max_size_mb)
      val ->
        case Integer.parse(val) do
          {num, _} -> num
          :error -> @default_max_size_mb
        end
    end
  end

  defp artifacts_dir do
    System.get_env("ARTIFACTS_DIR") || "artifacts"
  end

  @doc """
  Returns the recursive size of a file or directory in bytes.
  """
  def get_dir_size(path) do
    if File.dir?(path) do
      dir_contents_size(path)
    else
      file_size(path)
    end
  end

  defp dir_contents_size(path) do
    case File.ls(path) do
      {:ok, names} ->
        Enum.reduce(names, 0, fn name, acc ->
          acc + get_dir_size(Path.join(path, name))
        end)
      _ ->
        0
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.size
      _ -> 0
    end
  end

  # Purges old completed stage instances' artifacts
  defp purge_old_artifacts(bytes_to_free) do
    # 1. Query completed stage instances ordered by completed_at ascending (oldest first)
    completed_stages =
      StageInstance
      |> where(state: "Completed", artifacts_deleted: false)
      |> order_by(asc: :completed_at)
      |> Repo.all()
      |> Repo.preload([pipeline_instance: [pipeline: :stages]])

    # 2. Iterate and delete those that are not protected
    Enum.reduce_while(completed_stages, bytes_to_free, fn stage_instance, remaining_bytes ->
      if remaining_bytes <= 0 do
        {:halt, remaining_bytes}
      else
        purge_stage_if_not_protected(stage_instance, remaining_bytes)
      end
    end)
  end

  defp purge_stage_if_not_protected(stage_instance, remaining_bytes) do
    pipeline_instance = stage_instance.pipeline_instance
    pipeline = pipeline_instance.pipeline

    cond do
      # Check never_cleanup_artifacts from pipeline stage config
      stage_protected_by_config?(pipeline, stage_instance.name) ->
        {:cont, remaining_bytes}

      # "always keeping the last job's run's artifacts"
      latest_run?(pipeline.id, stage_instance.name, stage_instance) ->
        {:cont, remaining_bytes}

      true ->
        delete_stage_artifacts(stage_instance, pipeline, pipeline_instance, remaining_bytes)
    end
  end

  defp delete_stage_artifacts(stage_instance, pipeline, pipeline_instance, remaining_bytes) do
    stage_dir = Path.expand(Path.join([
      artifacts_dir(),
      pipeline.name,
      to_string(pipeline_instance.counter),
      stage_instance.name,
      to_string(stage_instance.counter)
    ]))

    size = get_dir_size(stage_dir)

    case File.rm_rf(stage_dir) do
      {:ok, _} ->
        Logger.info("Cleaned up artifacts for stage: #{pipeline.name}/#{pipeline_instance.counter}/#{stage_instance.name}/#{stage_instance.counter} (freed #{size} bytes)")

        # Mark as deleted in DB
        stage_instance
        |> StageInstance.changeset(%{artifacts_deleted: true})
        |> Repo.update!()

        {:cont, remaining_bytes - size}

      {:error, reason, _file} ->
        Logger.error("Failed to delete directory #{stage_dir}: #{inspect(reason)}")
        {:cont, remaining_bytes}
    end
  end

  defp stage_protected_by_config?(%Pipeline{stages: stages}, stage_name) do
    case Enum.find(stages || [], &(&1.name == stage_name)) do
      nil -> false
      stage_config -> stage_config.never_cleanup_artifacts
    end
  end

  defp latest_run?(pipeline_id, stage_name, stage_instance) do
    # A stage instance is the latest run of its stage config if its latest_run is true
    # or if no newer stage instance exists in the database.
    if stage_instance.latest_run do
      true
    else
      # Check if a newer stage instance exists for this stage config name under this pipeline
      query =
        from si in StageInstance,
          join: pi in PipelineInstance, on: si.pipeline_instance_id == pi.id,
          where: pi.pipeline_id == ^pipeline_id and si.name == ^stage_name and
            (pi.counter > ^stage_instance.pipeline_instance.counter or
             (pi.counter == ^stage_instance.pipeline_instance.counter and si.counter > ^stage_instance.counter))

      Repo.exists?(query) == false
    end
  end
end
