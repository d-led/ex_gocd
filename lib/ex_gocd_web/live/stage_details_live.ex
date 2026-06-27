defmodule ExGoCDWeb.StageDetailsLive do
  @moduledoc """
  LiveView for the Stage Details page.
  Renders breadcrumbs, run duration, stage parameters, job states, and simulated console outputs.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.MockData
  alias ExGoCD.Agents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      ExGoCD.PubSub.subscribe(ExGoCD.PubSub.pipeline_topic())
    end

    {:ok, assign(socket, :active_tab, "jobs")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    pipeline_name = params["pipeline_name"]
    pipeline_counter = String.to_integer(params["pipeline_counter"])
    stage_name = params["stage_name"]
    stage_counter = String.to_integer(params["stage_counter"])

    stage = get_stage_details(pipeline_name, pipeline_counter, stage_name, stage_counter)

    {:noreply,
     socket
     |> assign(:pipeline_name, pipeline_name)
     |> assign(:pipeline_counter, pipeline_counter)
     |> assign(:stage_name, stage_name)
     |> assign(:stage_counter, stage_counter)
     |> assign(:stage, stage)
     |> assign(
       :page_title,
       "#{pipeline_name} / #{pipeline_counter} / #{stage_name} / #{stage_counter}"
     )}
  end

  @impl true
  def handle_event("approve_stage", _params, socket) do
    user = socket.assigns[:current_user]

    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        pipeline_name = socket.assigns.pipeline_name
        counter = socket.assigns.pipeline_counter
        stage_name = socket.assigns.stage_name

        case ExGoCD.Pipelines.approve_stage(pipeline_name, counter, stage_name) do
          {:ok, _stage_instance} ->
            stage =
              get_stage_details(pipeline_name, counter, stage_name, socket.assigns.stage_counter)

            {:noreply,
             socket
             |> put_flash(:info, "Stage approved successfully.")
             |> assign(:stage, stage)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to approve stage: #{inspect(reason)}")}
        end

      false ->
        {:noreply,
         put_flash(socket, :error, "You do not have operate permissions for this pipeline.")}
    end
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_info({:pipeline_triggered, _name, _counter}, socket) do
    {:noreply, refresh_stage(socket)}
  end

  def handle_info(:pipelines_updated, socket) do
    {:noreply, refresh_stage(socket)}
  end

  defp refresh_stage(socket) do
    stage = get_stage_details(
      socket.assigns.pipeline_name,
      socket.assigns.pipeline_counter,
      socket.assigns.stage_name,
      socket.assigns.stage_counter
    )
    assign(socket, :stage, stage)
  end

  # Helpers

  defp use_mock?(name) do
    System.get_env("USE_MOCK_DATA") == "true" or not has_db_pipeline?(name)
  end

  defp has_db_pipeline?(name) do
    import Ecto.Query
    ExGoCD.Repo.exists?(from(p in ExGoCD.Pipelines.Pipeline, where: p.name == ^name))
  end

  defp get_stage_details(pipeline_name, pipeline_counter, stage_name, stage_counter) do
    if use_mock?(pipeline_name) do
      get_mock_stage_details(pipeline_name, pipeline_counter, stage_name, stage_counter)
    else
      import Ecto.Query

      ExGoCD.Repo.one(
        from si in ExGoCD.Pipelines.StageInstance,
          join: pi in ExGoCD.Pipelines.PipelineInstance,
          on: si.pipeline_instance_id == pi.id,
          join: p in ExGoCD.Pipelines.Pipeline,
          on: pi.pipeline_id == p.id,
          where:
            p.name == ^pipeline_name and pi.counter == ^pipeline_counter and
              si.name == ^stage_name and si.counter == ^stage_counter,
          preload: [job_instances: :stage_instance]
      )
      |> case do
        nil -> get_mock_stage_details(pipeline_name, pipeline_counter, stage_name, stage_counter)
        si -> map_db_stage(si)
      end
    end
  end

  defp map_db_stage(si) do
    %{
      name: si.name,
      counter: si.counter,
      state: si.state,
      result: si.result,
      duration: stage_duration(si),
      created_time: si.created_time,
      clean_working_dir: si.clean_working_dir,
      fetch_materials: si.fetch_materials,
      approval_type: si.approval_type,
      jobs: map_db_jobs(si.job_instances || [])
    }
  end

  defp map_db_jobs(job_instances) do
    # Pre-fetch all agents referenced by these job instances
    agent_uuids = Enum.map(job_instances, & &1.agent_uuid) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    agents_map = Agents.get_agents_by_uuids(agent_uuids)

    Enum.map(job_instances, fn ji ->
      agent = Map.get(agents_map, ji.agent_uuid)
      %{
        name: ji.name,
        state: ji.state,
        result: ji.result,
        agent_uuid: ji.agent_uuid,
        agent_resources: (agent && agent.resources) || [],
        agent_hostname: (agent && agent.hostname) || ji.agent_uuid,
        agent_type: agent_type(agent),
        duration: job_duration(ji),
        build_id: ji.id
      }
    end)
  end

  defp job_duration(ji) do
    case {ji.completed_at, ji.assigned_at} do
      {completed, assigned} when not is_nil(completed) and not is_nil(assigned) ->
        diff_seconds(completed, assigned)

      _ ->
        0
    end
  end

  defp stage_duration(si) do
    case {si.completed_at, si.created_time} do
      {completed, created} when not is_nil(completed) and not is_nil(created) ->
        diff_seconds(completed, created)

      _ ->
        0
    end
  end

  defp diff_seconds(t1, t2) do
    c_dt = to_utc_datetime(t1)
    cr_dt = to_utc_datetime(t2)
    if c_dt && cr_dt, do: DateTime.diff(c_dt, cr_dt, :second), else: 0
  end

  defp to_utc_datetime(%DateTime{} = dt), do: dt
  defp to_utc_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp to_utc_datetime(_), do: nil

  defp get_mock_stage_details(pipeline_name, _pipeline_counter, stage_name, stage_counter) do
    mock_pipeline = Enum.find(MockData.pipelines(), &(&1.name == pipeline_name))

    mock_stage =
      if mock_pipeline do
        Enum.find(mock_pipeline.stages || [], &(&1.name == stage_name))
      else
        nil
      end

    status = if mock_stage, do: mock_stage.status, else: "Passed"
    duration = if mock_stage, do: mock_stage.duration || 120, else: 120

    jobs = [
      %{
        name: "build_job",
        state: "Completed",
        result: status,
        agent_uuid: "agent-1111-2222-3333",
        agent_resources: ["mock"],
        agent_hostname: "mock-agent",
        agent_type: "mock",
        duration: duration,
        build_id: 1001
      }
    ]

    %{
      name: stage_name,
      counter: stage_counter,
      state: if(status == "Passed" or status == "Failed", do: "Completed", else: "Building"),
      result: status,
      duration: duration,
      created_time: ~U[2026-06-11 12:00:00Z],
      clean_working_dir: true,
      fetch_materials: true,
      approval_type: "success",
      jobs: jobs
    }
  end

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end

  defp format_duration(_), do: "—"

  defp status_bg_color(state, result) do
    cond do
      state == "Awaiting" -> "bg-[#e7eef0] border border-[#b6cdd2]"
      state == "Building" -> "bg-[#5bc0de]"
      result == "Passed" -> "bg-[#5cb85c]"
      result == "Failed" -> "bg-[#d9534f]"
      result == "Cancelled" -> "bg-[#f0ad4e]"
      true -> "bg-gray-400"
    end
  end

  defp agent_type(nil), do: "—"
  defp agent_type(agent) do
    sandbox = agent.sandbox || ""
    resources = agent.resources || []
    elastic_id = agent.elastic_profile_id

    cond do
      elastic_id && String.contains?(sandbox, "k8s") -> "k8s-elastic"
      elastic_id && String.contains?(sandbox, "docker") -> "docker-elastic"
      "k8s" in resources -> "k8s"
      "docker" in resources -> "docker"
      elastic_id -> "elastic"
      true -> "regular"
    end
  end

  defp kind_color("k8s-elastic"), do: "bg-purple-100 text-purple-700"
  defp kind_color("docker-elastic"), do: "bg-blue-100 text-blue-700"
  defp kind_color("docker"), do: "bg-cyan-100 text-cyan-700"
  defp kind_color("k8s"), do: "bg-purple-100 text-purple-700"
  defp kind_color("elastic"), do: "bg-teal-100 text-teal-700"
  defp kind_color("regular"), do: "bg-gray-100 text-gray-600"
  defp kind_color(_), do: "bg-gray-100 text-gray-400"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="stage-details-page px-8 py-8 bg-[#f4f8f9] min-h-screen">
      <div class="page-header border-b border-gray-200 pb-4 mb-6">
        <div class="flex items-center gap-2 text-xs text-gray-500 font-mono font-bold uppercase tracking-wider">
          <.link
            navigate={~p"/pipeline/activity/#{@pipeline_name}"}
            class="text-[#2d6ca2] hover:underline"
          >
            {@pipeline_name}
          </.link>
          <span>/</span>
          <.link
            navigate={~p"/pipelines/value_stream_map/#{@pipeline_name}/#{@pipeline_counter}"}
            class="text-[#2d6ca2] hover:underline"
          >
            {@pipeline_counter}
          </.link>
          <span>/</span>
          <span>{@stage_name}</span>
          <span>/</span>
          <span>{@stage_counter}</span>
        </div>

        <div class="flex items-center justify-between mt-2">
          <div class="flex items-center gap-4">
            <span class={"w-3.5 h-3.5 rounded-full " <> status_bg_color(@stage.state, @stage.result)}>
            </span>
            <h1 class="text-2xl font-extrabold text-gray-950 font-mono flex items-baseline gap-2">
              {@stage_name}
              <span class="text-sm font-semibold text-gray-500">Run Details</span>
            </h1>
          </div>
          <%= if @stage.state == "Awaiting" do %>
            <button
              type="button"
              class="bg-[#2d6ca2] hover:bg-[#24527d] text-white px-4 py-2 text-sm font-bold font-mono rounded flex items-center gap-1.5 shadow"
              phx-click="approve_stage"
            >
              <i class="fa-solid fa-play text-xs"></i> Approve Stage
            </button>
          <% end %>
        </div>
      </div>

      <div class="flex flex-col gap-6">
        <div class="bg-white border border-gray-200 rounded shadow-sm p-6 flex flex-wrap justify-between items-center gap-6">
          <div class="flex flex-col gap-1.5">
            <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">
              Result
            </span>
            <span class="text-sm font-semibold text-gray-800 font-mono">
              {@stage.result} (State: {@stage.state})
            </span>
          </div>
          <div class="flex flex-col gap-1.5">
            <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">
              Duration
            </span>
            <span class="text-sm font-semibold text-gray-800 font-mono">
              {format_duration(@stage.duration)}
            </span>
          </div>
          <div class="flex flex-col gap-1.5">
            <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">
              Created Time
            </span>
            <span class="text-sm font-semibold text-gray-800 font-mono">
              {Calendar.strftime(@stage.created_time, "%Y-%m-%d %H:%M:%S UTC")}
            </span>
          </div>
        </div>

        <div class="bg-white border border-gray-200 rounded shadow-sm overflow-hidden">
          <nav class="flex border-b border-gray-200 bg-gray-50 px-4" aria-label="Tabs">
            <button
              phx-click="select_tab"
              phx-value-tab="jobs"
              class={"px-4 py-3 text-xs font-bold font-mono tracking-wide border-b-2 " <> if @active_tab == "jobs", do: "border-[#2d6ca2] text-[#2d6ca2]", else: "border-transparent text-gray-500 hover:text-gray-700"}
            >
              Jobs
            </button>
            <button
              phx-click="select_tab"
              phx-value-tab="config"
              class={"px-4 py-3 text-xs font-bold font-mono tracking-wide border-b-2 " <> if @active_tab == "config", do: "border-[#2d6ca2] text-[#2d6ca2]", else: "border-transparent text-gray-500 hover:text-gray-700"}
            >
              Configuration
            </button>
            <button
              phx-click="select_tab"
              phx-value-tab="console"
              class={"px-4 py-3 text-xs font-bold font-mono tracking-wide border-b-2 " <> if @active_tab == "console", do: "border-[#2d6ca2] text-[#2d6ca2]", else: "border-transparent text-gray-500 hover:text-gray-700"}
            >
              Console Log
            </button>
          </nav>

          <div class="p-6">
            <%= case @active_tab do %>
              <% "jobs" -> %>
                <div class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-gray-200 text-xs text-left">
                    <thead>
                      <tr class="bg-gray-50 text-[10px] uppercase font-bold text-gray-400 tracking-wider font-mono">
                        <th class="px-6 py-3">Job Name</th>
                        <th class="px-6 py-3">State</th>
                        <th class="px-6 py-3">Result</th>
                        <th class="px-6 py-3">Agent</th>
                        <th class="px-6 py-3">Kind</th>
                        <th class="px-6 py-3">Duration</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-100 font-mono text-gray-700">
                      <%= for job <- @stage.jobs do %>
                        <tr class="hover:bg-gray-50">
                          <td class="px-6 py-4 font-bold">
                            <.link
                              navigate={
                                ~p"/go/tab/build/detail/#{@pipeline_name}/#{@pipeline_counter}/#{@stage_name}/#{@stage_counter}/#{job.name}"
                              }
                              class="text-[#2d6ca2] hover:underline font-bold"
                            >
                              {job.name}
                            </.link>
                          </td>
                          <td class="px-6 py-4">{job.state}</td>
                          <td class="px-6 py-4">
                            <span class={"text-[9px] font-extrabold px-1.5 py-0.5 rounded uppercase font-mono text-white " <> status_bg_color(job.state, job.result)}>
                              {job.result}
                            </span>
                          </td>
                          <td class="px-6 py-4">
                            <%= if job.agent_uuid do %>
                              <.link navigate={~p"/agents"} class="text-[#2d6ca2] hover:underline">
                                {String.slice(job.agent_uuid, 0, 8)}
                              </.link>
                              <span :if={job.agent_resources != []} class="ml-1">
                                <%= for r <- job.agent_resources do %>
                                  <span class="text-[9px] bg-gray-100 text-gray-500 px-1 py-0.5 rounded font-mono">{r}</span>
                                <% end %>
                              </span>
                            <% else %>
                              —
                            <% end %>
                          </td>
                          <td class="px-6 py-4">
                            <span class={[
                              "text-[9px] font-bold px-1.5 py-0.5 rounded uppercase",
                              kind_color(job.agent_type)
                            ]}>
                              {job.agent_type}
                            </span>
                          </td>
                          <td class="px-6 py-4">{format_duration(job.duration)}</td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% "config" -> %>
                <div class="max-w-xl">
                  <table class="min-w-full text-xs font-mono text-gray-700">
                    <tbody class="divide-y divide-gray-100">
                      <tr>
                        <td class="py-3 font-bold text-gray-400 uppercase tracking-wider text-[9px] w-48">
                          Clean Working Directory
                        </td>
                        <td class="py-3">{to_string(@stage.clean_working_dir)}</td>
                      </tr>
                      <tr>
                        <td class="py-3 font-bold text-gray-400 uppercase tracking-wider text-[9px]">
                          Fetch Materials
                        </td>
                        <td class="py-3">{to_string(@stage.fetch_materials)}</td>
                      </tr>
                      <tr>
                        <td class="py-3 font-bold text-gray-400 uppercase tracking-wider text-[9px]">
                          Approval Type
                        </td>
                        <td class="py-3 text-cyan-600 font-bold">{@stage.approval_type}</td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              <% "console" -> %>
                <div class="bg-gray-900 rounded p-6 font-mono text-gray-300 text-xs overflow-y-auto max-h-[400px] leading-relaxed shadow-inner">
                  <div class="text-yellow-500">
                    [go] Start to build pipeline: {@pipeline_name} / {@pipeline_counter} ...
                  </div>
                  <div>[go] Fetching SCM materials from repository...</div>
                  <div class="text-green-500">[go] Material hash verification successful.</div>
                  <div>[go] Executing task command: mix compile</div>
                  <div class="text-gray-500">Compiling 12 files (.ex)</div>
                  <div class="text-gray-500">Generated ex_gocd app</div>
                  <div>[go] Executing task command: mix test</div>
                  <div class="text-gray-500">Finished in 1.4 seconds</div>
                  <div class="text-gray-500">238 tests, 0 failures</div>
                  <div class="text-green-500 font-bold">
                    [go] Job 'build_job' completed successfully with result: {@stage.result}.
                  </div>
                  <div class="text-yellow-500">
                    [go] Stage completed. Invalidation triggers cleared.
                  </div>
                </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
