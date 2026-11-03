defmodule ExGoCDWeb.API.StageController do
  use ExGoCDWeb, :controller

  # GoCD asks an empty mutating request to carry X-GoCD-Confirm; see the plug.
  plug ExGoCDWeb.Plugs.GoCDConfirm

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{JobInstance, StageInstance}

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
    with {:ok, pipeline_counter} <- parse_counter(counter_str),
         {:ok, stage_counter} <- parse_counter(stage_counter_str) do
      case Pipelines.get_stage_instance(
             pipeline_name,
             pipeline_counter,
             stage_name,
             stage_counter
           ) do
        nil ->
          conn |> put_status(:not_found) |> json(%{message: "Stage instance not found."})

        si ->
          json(conn, stage_json(si))
      end
    else
      {:error, :not_a_counter} -> not_a_counter(conn, "pipeline and stage counters")
    end
  end

  @doc """
  GET /api/stages/:pipeline_name/:stage_name/history
  """
  def history(conn, %{"pipeline_name" => pipeline_name, "stage_name" => stage_name}) do
    offset = parse_offset(conn.params["offset"])

    instances =
      Pipelines.list_stage_instances(pipeline_name, stage_name, offset: offset, limit: 25)

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
  POST /api/stages/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/cancel

  GoCD names the stage instance with its counter; the counter-less path is ours
  and stays, because our own pages call it.
  """
  def cancel(
        conn,
        %{
          "pipeline_name" => pipeline_name,
          "pipeline_counter" => counter_str,
          "stage_name" => stage_name
        } = params
      ) do
    actor = get_actor(conn)
    remote_ip = get_remote_ip(conn)

    with {:ok, pipeline_counter} <- parse_counter(counter_str),
         {:ok, stage_counter} <- parse_optional_counter(params["stage_counter"]) do
      case Pipelines.cancel_stage(pipeline_name, pipeline_counter, stage_name,
             actor: actor,
             remote_ip: remote_ip,
             stage_counter: stage_counter
           ) do
        {:ok, _} ->
          json(conn, %{message: "Stage cancelled successfully."})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{message: "Cancel failed: #{reason}"})
      end
    else
      {:error, :not_a_counter} -> not_a_counter(conn, "pipeline and stage counters")
    end
  end

  # Only the counter-less route leaves this out.
  defp parse_optional_counter(nil), do: {:ok, nil}
  defp parse_optional_counter(value), do: parse_counter(value)

  @doc "POST /api/stages/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/run-failed-jobs"
  def run_failed_jobs(conn, params) do
    with_stage_instance(conn, params, &Pipelines.rerun_failed_jobs/4)
  end

  @doc "POST /api/stages/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/run-selected-jobs"
  def run_selected_jobs(conn, %{"jobs" => [_ | _]} = params) do
    with_stage_instance(
      conn,
      params,
      &Pipelines.rerun_selected_jobs(&1, &2, &3, &4, params["jobs"])
    )
  end

  def run_selected_jobs(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{message: "Following property must be specified: jobs (a list of job names)."})
  end

  defp with_stage_instance(conn, params, rerun) do
    with {:ok, pipeline_counter} <- parse_counter(params["pipeline_counter"]),
         {:ok, stage_counter} <- parse_counter(params["stage_counter"]) do
      rerun.(params["pipeline_name"], pipeline_counter, params["stage_name"], stage_counter)
      |> respond(conn)
    else
      {:error, :not_a_counter} -> not_a_counter(conn, "pipeline and stage counters")
    end
  end

  defp respond({:ok, _count}, conn) do
    conn |> put_status(:accepted) |> json(%{message: "Request to rerun jobs accepted"})
  end

  defp respond({:error, :stage_not_found}, conn) do
    conn |> put_status(:not_found) |> json(%{message: "Stage not found."})
  end

  defp respond({:error, reason}, conn) do
    conn |> put_status(:unprocessable_entity) |> json(%{message: rerun_refusal(reason)})
  end

  defp rerun_refusal(:no_failed_jobs), do: "No failed jobs to rerun."
  defp rerun_refusal(:no_such_jobs), do: "None of those jobs belong to this stage."
  defp rerun_refusal(other), do: "Rerun failed: #{other}"

  defp not_a_counter(conn, what) do
    conn
    |> put_status(:bad_request)
    |> json(%{message: "#{String.capitalize(what)} must be whole numbers."})
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
      jobs: Enum.map(loaded(si.job_instances), &job_json/1)
    }
  end

  # A preloaded association is a list; one that was left out is NotLoaded, which
  # has no rows to show rather than no value.
  defp loaded(jobs) when is_list(jobs), do: jobs
  defp loaded(_not_loaded), do: []

  defp job_json(%JobInstance{} = ji) do
    %{
      name: ji.name,
      state: ji.state || "Scheduled",
      result: ji.result || "Unknown",
      scheduled_at: format_ts(ji.scheduled_at)
    }
  end
end
