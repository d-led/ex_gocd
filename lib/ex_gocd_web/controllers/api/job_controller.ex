# Copyright 2026 ex_gocd
# API to schedule a job (enqueue for assignment to an idle agent).
# GoCD domain: pipeline → stage → job; one execution = job run (build).

defmodule ExGoCDWeb.API.JobController do
  @moduledoc """
  Schedule a job for assignment to an idle agent (GoCD-style scheduler).

  POST /api/jobs/schedule
  Body (optional): %{"pipeline" => _, "stage" => _, "job" => _, "resources" => [], "environments" => []}
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Scheduler

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
end
