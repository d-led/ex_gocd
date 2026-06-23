defmodule ExGoCDWeb.API.DashboardController do
  use ExGoCDWeb, :controller

  import Ecto.Query

  alias ExGoCD.{Repo}
  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance}

  @doc """
  GET /api/dashboard — GoCD v4-compatible dashboard JSON.
  Returns pipeline groups with latest instance status.
  """
  def show(conn, _params) do
    pipelines = Repo.all(from p in Pipeline, order_by: [asc: :display_order_weight, asc: :name])

    pipeline_data =
      Enum.map(pipelines, fn p ->
        latest = latest_instance(p.id)

        %{
          name: p.name,
          group: p.group || "defaultGroup",
          paused: p.paused || false,
          locked: p.locked || false,
          latest_instance: instance_summary(latest, p.name)
        }
      end)

    # Group by pipeline group
    grouped =
      pipeline_data
      |> Enum.group_by(& &1.group)
      |> Enum.map(fn {group_name, pipes} ->
        %{
          name: group_name,
          pipelines: pipes
        }
      end)

    json(conn, %{
      pipeline_groups: grouped,
      _links: %{
        self: %{href: "/api/dashboard"},
        doc: %{href: "https://api.gocd.org/current/#dashboard"}
      }
    })
  end

  defp latest_instance(pipeline_id) do
    import Ecto.Query

    Repo.one(
      from pi in PipelineInstance,
        where: pi.pipeline_id == ^pipeline_id,
        order_by: [desc: :counter],
        limit: 1,
        preload: [stage_instances: [job_instances: :job]]
    )
  end

  defp instance_summary(nil, pipe_name) do
    %{counter: 0, name: pipe_name, stages: [], status: "NeverRun"}
  end

  defp instance_summary(pi, _pipe_name) do
    stages = pi.stage_instances || []

    %{
      counter: pi.counter,
      label: pi.label || to_string(pi.counter),
      scheduled_at: ts(pi.inserted_at),
      stages:
        Enum.map(stages, fn si ->
          %{
            name: si.name,
            counter: si.counter,
            status: si.state || "Unknown",
            result: si.result || "Unknown",
            rerun_of_counter: si.rerun_of_counter,
            jobs:
              Enum.map(si.job_instances || [], fn ji ->
                %{
                  name: ji.name,
                  state: ji.state || "Unknown",
                  result: ji.result || "Unknown",
                  scheduled_date: ts(ji.scheduled_at)
                }
              end)
          }
        end),
      # Pipeline-level status derived from stages
      status: pipeline_status(stages)
    }
  end

  defp pipeline_status([]), do: "NeverRun"

  defp pipeline_status(stages) do
    states = Enum.map(stages, &(&1.state || "Unknown"))
    results = Enum.map(stages, &(&1.result || "Unknown"))

    cond do
      Enum.any?(states, &(&1 in ["Building", "Awaiting"])) -> "Building"
      Enum.all?(results, &(&1 == "Passed")) -> "Passed"
      Enum.any?(results, &(&1 == "Failed")) -> "Failed"
      Enum.any?(results, &(&1 == "Cancelled")) -> "Cancelled"
      true -> "Unknown"
    end
  end

  defp ts(nil), do: nil
  defp ts(dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")
end
