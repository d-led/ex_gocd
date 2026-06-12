defmodule ExGoCDWeb.PipelineActivityLive do
  @moduledoc """
  LiveView for the Pipeline Activity (History) page.
  Lists all historical runs of a pipeline, their triggering causes, SCM commits, and stage grids.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.MockData
  alias ExGoCD.Pipelines

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    name = params["pipeline_name"]

    pipeline =
      if use_mock?(name) do
        mock_p = Enum.find(MockData.pipelines(), &(&1.name == name))
        if mock_p, do: %{name: name, group: mock_p.group}, else: nil
      else
        Pipelines.get_pipeline_by_name(name)
      end

    if is_nil(pipeline) do
      {:noreply,
       socket
       |> put_flash(:error, "Pipeline '#{name}' not found.")
       |> redirect(to: "/pipelines")}
    else
      runs = get_pipeline_runs(name)
      {:noreply,
       socket
       |> assign(:pipeline, pipeline)
       |> assign(:runs, runs)
       |> assign(:page_title, "#{name} Activity")}
    end
  end

  # Helper functions

  defp use_mock?(name) do
    System.get_env("USE_MOCK_DATA") == "true" or not has_db_pipeline?(name)
  end

  defp has_db_pipeline?(name) do
    import Ecto.Query
    ExGoCD.Repo.exists?(from(p in ExGoCD.Pipelines.Pipeline, where: p.name == ^name))
  end

  defp get_pipeline_runs(pipeline_name) do
    if use_mock?(pipeline_name),
      do: get_mock_runs(pipeline_name),
      else: db_pipeline_runs(pipeline_name)
  end

  defp db_pipeline_runs(pipeline_name) do
    case Pipelines.get_pipeline_by_name(pipeline_name) do
      nil ->
        get_mock_runs(pipeline_name)

      p ->
        import Ecto.Query

        runs =
          ExGoCD.Repo.all(
            from pi in ExGoCD.Pipelines.PipelineInstance,
              where: pi.pipeline_id == ^p.id,
              order_by: [desc: pi.counter],
              preload: [stage_instances: :job_instances]
          )
          |> Enum.map(&map_pipeline_instance/1)

        if runs == [], do: get_mock_runs(pipeline_name), else: runs
    end
  end

  defp map_pipeline_instance(pi) do
    build_cause = pi.build_cause || %{}

    %{
      counter: pi.counter,
      label: pi.label,
      status: pipeline_instance_status(pi),
      triggered_by: build_cause["triggerMessage"] || "Triggered manually",
      last_run: pi.inserted_at || pi.updated_at || DateTime.utc_now(),
      stages: pi.stage_instances |> Enum.sort_by(& &1.order_id) |> Enum.map(&map_stage_instance/1),
      modifications: build_cause["materialRevisions"] |> List.wrap() |> Enum.flat_map(&map_modifications/1)
    }
  end

  defp map_stage_instance(si) do
    %{name: si.name, status: stage_status(si), counter: si.counter}
  end

  defp map_modifications(rev) do
    fp = fingerprint(rev)

    (rev["modifications"] || [])
    |> Enum.map(fn mod ->
      %{
        revision: mod["revision"] || "unknown",
        user: mod["username"] || "anonymous",
        comment: mod["comment"] || "",
        fingerprint: fp
      }
    end)
  end

  defp stage_status(si) do
    case {si.state, si.result} do
      {"Building", _} -> "Building"
      {"Completed", "Passed"} -> "Passed"
      {"Completed", "Failed"} -> "Failed"
      {"Completed", "Cancelled"} -> "Cancelled"
      _ -> "NotRun"
    end
  end

  defp pipeline_instance_status(pi) do
    stages = pi.stage_instances || []

    cond do
      Enum.any?(stages, fn s -> s.state == "Building" end) -> "Building"
      Enum.any?(stages, fn s -> s.result == "Failed" or s.result == "Cancelled" end) -> "Failed"
      Enum.all?(stages, fn s -> s.state == "Completed" and s.result == "Passed" end) -> "Passed"
      true -> "Unknown"
    end
  end

  defp fingerprint(rev) do
    type = rev["type"] || "git"
    url = rev["url"] || ""
    branch = rev["branch"] || ""

    :crypto.hash(:sha256, "#{type}-#{url}-#{branch}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp get_mock_runs(pipeline_name) do
    mock_pipeline = Enum.find(MockData.pipelines(), &(&1.name == pipeline_name))
    base_counter = if mock_pipeline, do: mock_pipeline.counter, else: 145

    [
      %{
        counter: base_counter,
        label: to_string(base_counter),
        status: if(mock_pipeline, do: mock_pipeline.status, else: "Passed"),
        triggered_by:
          if(mock_pipeline, do: mock_pipeline.triggered_by, else: "Triggered by dmitry"),
        last_run: ~U[2026-06-11 12:00:00Z],
        stages:
          if mock_pipeline do
            Enum.map(mock_pipeline.stages, &%{name: &1.name, status: &1.status, counter: 1})
          else
            [%{name: "compile", status: "Passed", counter: 1}, %{name: "test", status: "Passed", counter: 1}]
          end,
        modifications: [
          %{
            revision: "05172d07f4f4a0765243628b94f6840f8dc5411a",
            user: "Dmitry Ledentsov <dmlled@yahoo.com>",
            comment: "upgrade actions and fix compilation warnings",
            fingerprint: "8d78bc9f6c661806"
          }
        ]
      },
      %{
        counter: base_counter - 1,
        label: to_string(base_counter - 1),
        status: "Failed",
        triggered_by: "Triggered by dmitry",
        last_run: ~U[2026-06-11 10:30:00Z],
        stages:
          if mock_pipeline do
            Enum.map(
              mock_pipeline.stages,
              &%{name: &1.name, status: if(&1.name == "test", do: "Failed", else: "Passed"), counter: 1}
            )
          else
            [%{name: "compile", status: "Passed", counter: 1}, %{name: "test", status: "Failed", counter: 1}]
          end,
        modifications: [
          %{
            revision: "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0",
            user: "Dmitry Ledentsov <dmlled@yahoo.com>",
            comment: "add test suite support",
            fingerprint: "8d78bc9f6c661806"
          }
        ]
      },
      %{
        counter: base_counter - 2,
        label: to_string(base_counter - 2),
        status: "Passed",
        triggered_by: "Triggered manually by admin",
        last_run: ~U[2026-06-11 08:15:00Z],
        stages:
          if mock_pipeline do
            Enum.map(mock_pipeline.stages, &%{name: &1.name, status: "Passed", counter: 1})
          else
            [%{name: "compile", status: "Passed", counter: 1}, %{name: "test", status: "Passed", counter: 1}]
          end,
        modifications: [
          %{
            revision: "f0e1d2c3b4a5968776655443322110abcdef0123",
            user: "gocd-admin <admin@gocd.org>",
            comment: "initial configuration setup",
            fingerprint: "8d78bc9f6c661806"
          }
        ]
      }
    ]
  end

  defp format_local_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp stage_status_class(status) do
    case status do
      "Passed" -> "bg-[#5cb85c] hover:bg-[#4cae4c]"
      "Failed" -> "bg-[#d9534f] hover:bg-[#d43f3a]"
      "Building" -> "bg-[#5bc0de] hover:bg-[#46b8da]"
      "Cancelled" -> "bg-[#f0ad4e] hover:bg-[#eea236]"
      _ -> "bg-gray-300 hover:bg-gray-400"
    end
  end

  defp run_status_border(status) do
    case status do
      "Passed" -> "border-l-4 border-l-[#5cb85c]"
      "Failed" -> "border-l-4 border-l-[#d9534f]"
      "Building" -> "border-l-4 border-l-[#5bc0de]"
      _ -> "border-l-4 border-l-gray-300"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pipeline-activity-page px-8 py-8 bg-[#f4f8f9] min-h-screen">
      <div class="page-header flex justify-between items-center border-b border-gray-200 pb-4 mb-6">
        <div class="flex flex-col">
          <div class="flex items-center gap-2 text-xs text-gray-500 font-mono font-bold uppercase tracking-wider">
            <.link navigate={~p"/pipelines"} class="text-[#2d6ca2] hover:underline">Pipelines</.link>
            <span>/</span>
            <span>{@pipeline.group}</span>
          </div>
          <h1 class="text-2xl font-extrabold text-gray-950 mt-1 flex items-center gap-2">
            {@pipeline.name}
            <span class="text-sm font-semibold text-gray-500 font-mono">History</span>
          </h1>
        </div>
      </div>

      <div class="activity-container flex flex-col gap-4">
        <%= for run <- @runs do %>
          <div class={"pipeline-run-row flex items-stretch bg-white border border-gray-200 rounded shadow-sm hover:shadow-md transition-shadow " <> run_status_border(run.status)}>
            <div class="p-5 flex-shrink-0 w-44 border-r border-gray-100 flex flex-col justify-between">
              <div>
                <span class="text-[10px] uppercase font-bold text-gray-400 tracking-wider font-mono">Instance</span>
                <div class="text-lg font-mono font-extrabold text-gray-900 mt-0.5">#{run.label}</div>
              </div>
              <div class="mt-4 flex flex-col gap-1.5 text-xs">
                <.link navigate={~p"/pipelines/value_stream_map/#{@pipeline.name}/#{run.counter}"} class="text-[#2d6ca2] hover:underline font-bold flex items-center gap-1">
                  <i class="fa-solid fa-network-wired text-[10px]"></i> VSM
                </.link>
                <%= if run.counter > 1 do %>
                  <a href={"/compare/#{@pipeline.name}/#{run.counter - 1}/with/#{run.counter}"} class="text-[#2d6ca2] hover:underline font-bold flex items-center gap-1">
                    <i class="fa-solid fa-right-left text-[10px]"></i> Compare
                  </a>
                <% end %>
              </div>
            </div>

            <div class="p-5 flex-grow min-w-0 flex flex-col justify-between">
              <div>
                <div class="flex justify-between items-start gap-4">
                  <div class="text-xs text-gray-500 font-medium">
                    <span class="font-bold text-gray-700">{run.triggered_by}</span> on {format_local_time(run.last_run)}
                  </div>
                  <span class={"text-[9px] font-extrabold px-1.5 py-0.5 rounded uppercase font-mono " <>
                    case run.status do
                      "Passed" -> "bg-green-100 text-green-700"
                      "Failed" -> "bg-red-100 text-red-700"
                      "Building" -> "bg-blue-100 text-blue-700"
                      _ -> "bg-gray-100 text-gray-700"
                    end}>
                    {run.status}
                  </span>
                </div>

                <div class="mt-3">
                  <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">Trigger Revision Details</span>
                  <%= for mod <- run.modifications do %>
                    <div class="flex items-baseline gap-2 mt-1 text-xs text-gray-600">
                      <.link navigate={~p"/materials/value_stream_map/#{mod.fingerprint}/#{mod.revision}"} class="font-mono text-cyan-600 hover:underline">
                        {String.slice(mod.revision, 0, 8)}
                      </.link>
                      <span class="font-semibold text-gray-700 truncate w-32">{mod.user}:</span>
                      <span class="italic text-gray-600 truncate flex-grow">"{mod.comment}"</span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <div class="p-5 flex-shrink-0 w-72 border-l border-gray-100 flex flex-col justify-center">
              <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono mb-2 block text-center">Stages Run Details</span>
              <ul class="flex flex-wrap justify-center gap-1.5">
                <%= for stage <- run.stages do %>
                  <li class="relative">
                    <.link
                      navigate={~p"/pipelines/#{@pipeline.name}/#{run.counter}/#{stage.name}/#{stage.counter}"}
                      class={"w-8 h-8 flex items-center justify-center rounded text-white font-mono font-bold text-[10px] transition-transform hover:scale-105 shadow-sm " <> stage_status_class(stage.status)}
                      title={"#{stage.name} (#{stage.status})"}
                      aria-label={"#{stage.name} (#{stage.status})"}
                    >
                      {String.slice(stage.name, 0, 2) |> String.upcase()}
                    </.link>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
