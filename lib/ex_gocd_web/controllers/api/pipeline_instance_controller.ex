defmodule ExGoCDWeb.API.PipelineInstanceController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{JobInstance, PipelineInstance, StageInstance}
  alias ExGoCD.Repo

  @doc """
  GET /api/pipelines/:name/history
  Returns paginated pipeline instance history (GoCD v1 format).
  """
  def history(conn, %{"pipeline_name" => name}) do
    offset = parse_offset(conn.params["offset"])
    page_size = 10

    pipeline = Pipelines.get_pipeline_by_name(name)

    if is_nil(pipeline) do
      conn |> put_status(:not_found) |> json(%{message: "Pipeline '#{name}' not found."})
    else
      instances = Pipelines.list_pipeline_instances(pipeline.id, offset: offset, limit: page_size)
      total = Pipelines.count_pipeline_instances(pipeline.id)

      json(conn, %{
        pipelines: Enum.map(instances, &instance_to_json/1),
        pagination: %{offset: offset, page_size: page_size, total: total}
      })
    end
  end

  @doc """
  GET /api/pipelines/:name/:counter
  Returns a single pipeline instance (GoCD v1 format).
  """
  def show(conn, %{"pipeline_name" => name, "counter" => counter_str}) do
    case parse_counter(counter_str) do
      {:ok, counter} ->
        show_instance(conn, name, counter)

      {:error, :not_a_counter} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Pipeline counter must be a whole number."})
    end
  end

  defp show_instance(conn, name, counter) do
    case Pipelines.get_pipeline_instance(name, counter) do
      nil ->
        conn |> put_status(:not_found) |> json(%{message: "Pipeline instance not found."})

      instance ->
        json(conn, instance_to_json(instance))
    end
  end

  # ── JSON serialization ─────────────────────────────────────────────

  defp instance_to_json(%PipelineInstance{} = pi) do
    pi = Repo.preload(pi, [:pipeline, stage_instances: [job_instances: :job]])
    pipeline = pi.pipeline

    %{
      name: pipeline.name,
      counter: pi.counter,
      label: pi.label || "",
      scheduled_date: format_timestamp(pi.inserted_at),
      natural_order: pi.natural_order || 0.0,
      stages: Enum.map(pi.stage_instances || [], &stage_instance_json/1),
      build_cause: build_cause_json(pi)
    }
  end

  defp stage_instance_json(%StageInstance{} = si) do
    %{
      name: si.name,
      counter: si.counter,
      status: si.state || "Unknown",
      approval_type: si.approval_type || "success",
      scheduled: si.scheduled_at != nil,
      rerun_of_counter: si.rerun_of_counter,
      jobs: Enum.map(si.job_instances || [], &job_instance_json/1)
    }
  end

  defp job_instance_json(%JobInstance{} = ji) do
    %{
      name: ji.name,
      state: ji.state || "Scheduled",
      result: ji.result || "Unknown",
      scheduled_date: format_timestamp(ji.scheduled_at || ji.inserted_at)
    }
  end

  # What triggered a run is stored in `build_cause`, which the trigger path fills
  # in; there is no column per field.
  defp build_cause_json(pi) do
    cause = pi.build_cause || %{}

    %{
      trigger_message: cause["trigger_message"] || "Forced by user",
      trigger_forced: cause["trigger_forced"] == true,
      approver: cause["approver"],
      material_revisions: []
    }
  end

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")
  end
end
