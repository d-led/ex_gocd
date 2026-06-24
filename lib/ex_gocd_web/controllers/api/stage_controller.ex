defmodule ExGoCDWeb.API.StageController do
  use ExGoCDWeb, :controller

  alias ExGoCD.{Pipelines, Repo}
  alias ExGoCD.Pipelines.{StageInstance, JobInstance}

  defp get_actor(conn) do
    session = get_session(conn)
    ExGoCD.Accounts.get_current_user(session).username
  end

  defp get_remote_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  @doc """
  GET /api/stages/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter
  """
  def show(conn, %{
        "pipeline_name" => pipeline_name,
        "pipeline_counter" => counter_str,
        "stage_name" => stage_name,
        "stage_counter" => stage_counter_str
      }) do
    pipeline_counter = String.to_integer(counter_str)
    stage_counter = String.to_integer(stage_counter_str)

    import Ecto.Query

    si =
      from(si in StageInstance,
        join: pi in assoc(si, :pipeline_instance),
        join: p in assoc(pi, :pipeline),
        where:
          p.name == ^pipeline_name and
            pi.counter == ^pipeline_counter and
            si.name == ^stage_name and
            si.counter == ^stage_counter,
        preload: [pipeline_instance: {pi, pipeline: p}, job_instances: :job],
        limit: 1
      )
      |> Repo.one()

    if is_nil(si) do
      conn |> put_status(:not_found) |> json(%{message: "Stage instance not found."})
    else
      json(conn, stage_json(si))
    end
  end

  @doc """
  GET /api/stages/:pipeline_name/:stage_name/history
  """
  def history(conn, %{"pipeline_name" => pipeline_name, "stage_name" => stage_name}) do
    offset = parse_offset(conn.params["offset"])

    import Ecto.Query

    instances =
      from(si in StageInstance,
        join: pi in assoc(si, :pipeline_instance),
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and si.name == ^stage_name,
        order_by: [desc: pi.counter, desc: si.counter],
        offset: ^offset,
        limit: 25,
        preload: [pipeline_instance: {pi, pipeline: p}]
      )
      |> Repo.all()

    json(conn, %{
      stages:
        Enum.map(instances, fn si ->
          %{
            pipeline_name: pipeline_name,
            pipeline_counter: si.pipeline_instance.counter,
            name: stage_name,
            counter: si.counter,
            state: si.state || "Unknown",
            result: si.result || "Unknown",
            approval_type: si.approval_type || "success",
            rerun_of_counter: si.rerun_of_counter
          }
        end)
    })
  end

  @doc """
  POST /api/stages/:pipeline_name/:pipeline_counter/:stage_name/cancel
  """
  def cancel(conn, %{
        "pipeline_name" => pipeline_name,
        "pipeline_counter" => counter_str,
        "stage_name" => stage_name
      }) do
    pipeline_counter = String.to_integer(counter_str)
    actor = get_actor(conn)
    remote_ip = get_remote_ip(conn)

    case Pipelines.cancel_stage(pipeline_name, pipeline_counter, stage_name,
           actor: actor,
           remote_ip: remote_ip
         ) do
      {:ok, _} ->
        json(conn, %{message: "Stage '#{stage_name}' cancelled."})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{message: "Cancel failed: #{reason}"})
    end
  end

  @doc "POST /api/stages/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/rerun-failed-jobs"
  def rerun_failed_jobs(conn, %{
        "pipeline_name" => pipeline_name,
        "pipeline_counter" => counter_str,
        "stage_name" => stage_name,
        "stage_counter" => stage_counter_str
      }) do
    pipeline_counter = String.to_integer(counter_str)
    stage_counter = String.to_integer(stage_counter_str)

    case Pipelines.rerun_failed_jobs(pipeline_name, pipeline_counter, stage_name, stage_counter) do
      {:ok, count} ->
        json(conn, %{message: "Re-running #{count} failed job(s) in stage '#{stage_name}'."})

      {:error, :stage_not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Stage not found."})

      {:error, :no_failed_jobs} ->
        conn |> put_status(:unprocessable_entity) |> json(%{message: "No failed jobs to re-run."})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{message: "Re-run failed: #{reason}"})
    end
  end

  defp stage_json(%StageInstance{} = si) do
    %{
      name: si.name,
      counter: si.counter,
      state: si.state || "Unknown",
      result: si.result || "Unknown",
      approval_type: si.approval_type || "success",
      approved_by: si.approved_by,
      cancelled_by: si.cancelled_by,
      rerun_of_counter: si.rerun_of_counter,
      scheduled_at: format_ts(si.scheduled_at),
      completed_at: format_ts(si.completed_at),
      jobs: Enum.map(si.job_instances || [], &job_json/1)
    }
  end

  defp job_json(%JobInstance{} = ji) do
    %{
      name: ji.name,
      state: ji.state || "Scheduled",
      result: ji.result || "Unknown",
      scheduled_at: format_ts(ji.scheduled_at)
    }
  end
end
