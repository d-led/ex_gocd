defmodule ExGoCDWeb.API.AgentJobHistoryController do
  @moduledoc """
  `GET /go/api/agents/:uuid/job_run_history` — the jobs one agent completed,
  each with the states it went through.

  GoCD keeps this to admins (`AgentJobHistoryControllerV1` checks for one), and
  the route sits in the admin half of the agents scope for that reason.

  Paged by `offset` and `page_size` (10 to 100), sorted by `sort_column`
  (`pipeline`, `stage`, `job`, `result`, `completed`, `duration`) and
  `sort_order` (`ASC`, `DESC`). A value outside those is a 400 naming what is
  allowed, as in GoCD, rather than a silently different page of jobs.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents

  @default_page_size 10
  @page_size_range 10..100
  @default_sort_column "completed"
  @sort_orders ["ASC", "DESC"]

  def index(conn, %{"uuid" => uuid} = params) do
    with {:ok, offset} <- offset(params),
         {:ok, page_size} <- page_size(params),
         {:ok, column} <- sort_column(params),
         {:ok, order} <- sort_order(params),
         {:ok, _agent} <- find_agent(uuid) do
      {jobs, total} =
        AgentJobRuns.completed_jobs(uuid, %{
          offset: offset,
          page_size: page_size,
          sort_column: column,
          sort_order: order
        })

      json(conn, present(uuid, jobs, %{offset: offset, page_size: page_size, total: total}))
    else
      {:error, :agent_not_found} -> not_found(conn, uuid)
      {:error, message} -> bad_request(conn, message)
    end
  end

  defp present(uuid, jobs, pagination) do
    %{
      _links: %{
        self: %{href: "/api/agents/#{uuid}/job_run_history"},
        doc: %{href: "https://api.gocd.org/current/#agent-job-run-history"},
        find: %{href: "/api/agents/#{uuid}"}
      },
      uuid: uuid,
      jobs: Enum.map(jobs, &job/1),
      pagination: pagination
    }
  end

  defp job(run) do
    %{
      job_state_transitions: Enum.map(run.transitions, &transition/1),
      job_name: run.job_name,
      stage_name: run.stage_name,
      stage_counter: to_string(run.stage_counter || 1),
      pipeline_name: run.pipeline_name,
      pipeline_counter: run.pipeline_counter,
      result: run.result || "Unknown",
      rerun: rerun?(run)
    }
  end

  defp transition(transition) do
    %{state_change_time: DateTime.to_iso8601(transition.changed_at), state: transition.state}
  end

  # A run knows it was a rerun through the job instance it ran for; a run with no
  # pipeline behind it (an ad hoc agent test) never is one.
  defp rerun?(%{job_instance: %{rerun: rerun}}), do: rerun == true
  defp rerun?(_run), do: false

  defp offset(params) do
    case params["offset"] do
      nil ->
        {:ok, 0}

      given ->
        case Integer.parse(given) do
          {value, ""} when value >= 0 -> {:ok, value}
          _ -> {:error, bad_offset()}
        end
    end
  end

  defp page_size(%{"page_size" => given}) do
    case Integer.parse(given) do
      {value, ""} when value in @page_size_range -> {:ok, value}
      _ -> {:error, bad_page_size()}
    end
  end

  defp page_size(_params), do: {:ok, @default_page_size}

  defp sort_column(%{"sort_column" => given}) do
    if given in AgentJobRuns.history_sort_columns() do
      {:ok, given}
    else
      {:error, bad_sort_column()}
    end
  end

  defp sort_column(_params), do: {:ok, @default_sort_column}

  defp sort_order(%{"sort_order" => given}) do
    if given in @sort_orders do
      {:ok, String.downcase(given) |> String.to_existing_atom()}
    else
      {:error, "The query parameter `sort_order` must be one of #{Enum.join(@sort_orders, ", ")}"}
    end
  end

  defp sort_order(_params), do: {:ok, :desc}

  defp bad_page_size do
    "The query parameter `page_size`, if specified must be a number between " <>
      "#{@page_size_range.first} and #{@page_size_range.last}."
  end

  defp bad_offset do
    "The query parameter `offset`, if specified must be a number greater or equal to 0."
  end

  defp bad_sort_column do
    "The query parameter `sort_column` must be one of " <>
      Enum.join(AgentJobRuns.history_sort_columns(), ", ")
  end

  defp find_agent(uuid) do
    case Agents.get_agent_by_uuid(uuid) do
      nil -> {:error, :agent_not_found}
      agent -> {:ok, agent}
    end
  end

  defp not_found(conn, uuid) do
    conn
    |> put_status(:not_found)
    |> json(%{message: "Agent with identifier '#{uuid}' was not found."})
  end

  defp bad_request(conn, message) do
    conn
    |> put_status(:bad_request)
    |> json(%{message: message})
  end
end
