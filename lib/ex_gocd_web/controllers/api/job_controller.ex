# Copyright 2026 ex_gocd
# API to schedule a job (enqueue for assignment to an idle agent).
# GoCD domain: pipeline → stage → job; one execution = job run (build).

defmodule ExGoCDWeb.API.JobController do
  @moduledoc """
  Job instance API matching GoCD's job-instance-v1 endpoints.

  POST /api/jobs/schedule — schedule a job
  GET /api/jobs/:pipeline/:counter/:stage/:counter/:job — get job instance
  GET /api/jobs/:pipeline/:stage/:job/history — job run history
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.{Scheduler, Repo}
  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Pipelines.JobInstance

  def schedule(conn, params) do
    spec = Map.take(params, ~w(pipeline stage job resources environments))

    case Scheduler.schedule_job(spec) do
      {:ok, job_id} ->
        conn
        |> put_status(:created)
        |> json(%{message: "Job scheduled.", job_id: job_id})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: "Failed to schedule job."})
    end
  end

  @doc """
  GET /api/jobs/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name
  """
  def show(conn, %{
        "pipeline_name" => pipeline_name,
        "pipeline_counter" => counter_str,
        "stage_name" => stage_name,
        "stage_counter" => stage_counter_str,
        "job_name" => job_name
      }) do
    pipeline_counter = String.to_integer(counter_str)
    stage_counter = String.to_integer(stage_counter_str)

    import Ecto.Query

    ji =
      from(ji in JobInstance,
        join: si in assoc(ji, :stage_instance),
        join: pi in assoc(si, :pipeline_instance),
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and
                 pi.counter == ^pipeline_counter and
                 si.name == ^stage_name and
                 si.counter == ^stage_counter and
                 ji.name == ^job_name,
        preload: [stage_instance: {si, pipeline_instance: {pi, pipeline: p}}],
        limit: 1
      )
      |> Repo.one()

    if is_nil(ji) do
      conn |> put_status(:not_found) |> json(%{message: "Job instance not found."})
    else
      run = AgentJobRuns.get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)

      json(conn, %{
        name: ji.name,
        state: ji.state || "Scheduled",
        result: ji.result || "Unknown",
        scheduled_date: format_ts(ji.scheduled_at || ji.inserted_at),
        agent_uuid: run && run.agent_uuid,
        build_id: run && run.build_id
      })
    end
  end

  @doc """
  GET /api/jobs/:pipeline_name/:stage_name/:job_name/history
  Returns the last 25 job runs ordered by pipeline counter descending.
  """
  def history(conn, %{"pipeline_name" => pipeline_name, "stage_name" => stage_name, "job_name" => job_name}) do
    offset = parse_offset(conn.params["offset"])

    import Ecto.Query

    query =
      from(ji in JobInstance,
        join: si in assoc(ji, :stage_instance),
        join: pi in assoc(si, :pipeline_instance),
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and si.name == ^stage_name and ji.name == ^job_name,
        order_by: [desc: pi.counter, desc: si.counter],
        offset: ^offset,
        limit: 25,
        preload: [stage_instance: {si, pipeline_instance: {pi, pipeline: p}}]
      )

    instances = Repo.all(query)

    json(conn, %{
      jobs: Enum.map(instances, fn ji ->
        %{
          pipeline_name: pipeline_name,
          pipeline_counter: ji.stage_instance.pipeline_instance.counter,
          stage_name: stage_name,
          stage_counter: ji.stage_instance.counter,
          name: ji.name,
          state: ji.state || "Scheduled",
          result: ji.result || "Unknown",
          scheduled_date: format_ts(ji.scheduled_at || ji.inserted_at)
        }
      end)
    })
  end

  defp format_ts(nil), do: nil
  defp format_ts(dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")

  defp parse_offset(nil), do: 0
  defp parse_offset(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end
end
