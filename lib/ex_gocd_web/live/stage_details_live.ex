defmodule ExGoCDWeb.StageDetailsLive do
  @moduledoc """
  LiveView for the Stage Details page.
  Renders breadcrumbs, run duration, stage parameters, job states, and simulated console outputs.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.Agents
  alias ExGoCD.Analytics
  alias ExGoCD.MockData

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
    trends = Analytics.stage_trends(pipeline_name, stage_name, 10)

    {:noreply,
     socket
     |> assign(:pipeline_name, pipeline_name)
     |> assign(:pipeline_counter, pipeline_counter)
     |> assign(:stage_name, stage_name)
     |> assign(:stage_counter, stage_counter)
     |> assign(:stage, stage)
     |> assign(:trends, trends)
     |> assign(
       :page_title,
       "#{pipeline_name} / #{pipeline_counter} / #{stage_name} / #{stage_counter}"
     )}
  end

  @impl true
  def handle_event("approve_stage", _params, socket) do
    user = socket.assigns[:current_user]

    pipeline_name = socket.assigns.pipeline_name
    pipeline = ExGoCD.Pipelines.get_pipeline_by_name(pipeline_name)

    env_ok =
      ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user)

    group_ok =
      ExGoCD.Policies.permit?(ExGoCD.Policies.PipelineGroupPolicy, :operate_pipeline, user,
        pipeline_group: (pipeline && pipeline.group) || "default"
      )

    if env_ok and group_ok do
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
    else
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
    stage =
      get_stage_details(
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
    agent_uuids =
      Enum.map(job_instances, & &1.agent_uuid) |> Enum.reject(&is_nil/1) |> Enum.uniq()

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
        scheduled_at: ji.scheduled_at,
        assigned_at: ji.assigned_at,
        completed_at: ji.completed_at,
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
    classify_agent(
      agent.elastic_agent_id,
      agent.elastic_plugin_id || "",
      agent.working_dir || "",
      agent.resources || []
    )
  end

  defp classify_agent(nil, _plugin, _wd, resources) do
    cond do
      "k8s" in resources -> "k8s"
      "docker" in resources -> "docker"
      true -> "regular"
    end
  end

  defp classify_agent(_elastic_id, plugin, wd, _resources) do
    cond do
      String.contains?(wd, "k8s") or String.contains?(plugin, "kubernetes") -> "k8s-elastic"
      String.contains?(wd, "docker") or String.contains?(plugin, "docker") -> "docker-elastic"
      true -> "elastic"
    end
  end

  defp kind_color("k8s-elastic"), do: "bg-purple-100 text-purple-700"
  defp kind_color("docker-elastic"), do: "bg-blue-100 text-blue-700"
  defp kind_color("docker"), do: "bg-cyan-100 text-cyan-700"
  defp kind_color("k8s"), do: "bg-purple-100 text-purple-700"
  defp kind_color("elastic"), do: "bg-teal-100 text-teal-700"
  defp kind_color("regular"), do: "bg-gray-100 text-gray-600"
  defp kind_color(_), do: "bg-gray-100 text-gray-400"

  # ── Job Gantt chart ────────────────────────────────────────────────────

  defp job_gantt(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-bold text-gray-800 mb-3 flex items-center gap-2">
        <i class="fa-solid fa-chart-gantt text-[#2d6ca2]"></i> Job Timeline
      </h3>

      <div class="flex items-center gap-4 mb-5 text-[10px] text-gray-500">
        <span class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded bg-gray-300"></span> Waiting
        </span>
        <span class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded bg-[#5cb85c]"></span> Passed
        </span>
        <span class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded bg-[#d9534f]"></span> Failed
        </span>
        <span class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded bg-[#5bc0de]"></span> Building
        </span>
      </div>

      <%= if @jobs == [] do %>
        <p class="text-gray-400 text-xs">No jobs to display.</p>
      <% else %>
        <% {min_ts, _max_ts, span_sec} = job_gantt_window(@jobs) %>
        <% label_w = 72 %>
        <% dur_w = 64 %>
        <% tick_count = 6 %>

        <div class="overflow-x-auto">
          <div class="min-w-[650px]">
            <%!-- Time axis --%>
            <div class="flex items-end border-b border-gray-300 pb-1.5 mb-1 text-[9px] text-gray-400 font-mono select-none">
              <span class="shrink-0" style={"width:#{label_w}px"}></span>
              <div class="flex-1 relative h-5">
                <%= for i <- 0..(tick_count - 1) do %>
                  <% pct = i / (tick_count - 1) * 100 %>
                  <% tick_ts = DateTime.add(min_ts, round(span_sec * i / (tick_count - 1)), :second) %>
                  <span class="absolute -translate-x-1/2" style={"left:#{Float.round(pct, 1)}%;top:0"}>
                    {Calendar.strftime(tick_ts, "%H:%M:%S")}
                  </span>
                  <span
                    class="absolute top-4 w-px h-1.5 bg-gray-300"
                    style={"left:#{Float.round(pct, 1)}%"}
                  >
                  </span>
                <% end %>
              </div>
              <span class="shrink-0" style={"width:#{dur_w}px"}></span>
            </div>

            <%!-- Job rows --%>
            <div class="flex flex-col gap-0.5">
              <%= for job <- @jobs do %>
                <% sched = job[:scheduled_at] %>
                <% assigned = job[:assigned_at] %>
                <% completed = job[:completed_at] %>
                <div class="flex items-center group hover:bg-gray-50 rounded-sm transition-colors">
                  <%!-- Label --%>
                  <.link
                    navigate={
                      ~p"/go/tab/build/detail/#{@pipeline_name}/#{@pipeline_counter}/#{@stage_name}/#{@stage_counter}/#{job.name}"
                    }
                    class="shrink-0 font-mono font-extrabold text-gray-900 text-xs hover:text-[#2d6ca2] py-1 pr-2 truncate"
                    style={"width:#{label_w}px"}
                    title={job.name}
                  >
                    {job.name}
                  </.link>

                  <%!-- Gantt area --%>
                  <div class="flex-1 h-6 relative">
                    <div class="absolute top-1/2 left-0 right-0 border-t border-gray-100 -mt-px">
                    </div>

                    <%!-- Wait bar: scheduled → assigned (or now if building) --%>
                    <%= if sched do %>
                      <% wait_end = assigned || completed || DateTime.utc_now() %>
                      <% w_left =
                        Float.round(max(DateTime.diff(sched, min_ts, :second), 0) / span_sec * 100, 1) %>
                      <% w_width =
                        max(
                          Float.round(DateTime.diff(wait_end, sched, :second) / span_sec * 100, 1),
                          0.3
                        ) %>
                      <div
                        class="absolute top-1.5 h-3 rounded-sm bg-gray-300 opacity-70"
                        style={"left:#{w_left}%;width:#{w_width}%"}
                        title={"Waiting: #{format_duration(DateTime.diff(wait_end, sched, :second))}"}
                      >
                      </div>
                    <% end %>

                    <%!-- Build bar: assigned → completed --%>
                    <%= if assigned && completed do %>
                      <% b_left =
                        Float.round(
                          max(DateTime.diff(assigned, min_ts, :second), 0) / span_sec * 100,
                          1
                        ) %>
                      <% b_width =
                        max(
                          Float.round(
                            DateTime.diff(completed, assigned, :second) / span_sec * 100,
                            1
                          ),
                          0.3
                        ) %>
                      <div
                        class={"absolute top-1.5 h-3 rounded-sm opacity-85 " <> job_bar_color(job.result)}
                        style={"left:#{b_left}%;width:#{b_width}%"}
                        title={"#{job.name}: #{job.result} — #{format_duration(DateTime.diff(completed, assigned, :second))}"}
                      >
                      </div>
                    <% end %>

                    <%!-- Building: assigned → now --%>
                    <%= if assigned && !completed && job.state == "Building" do %>
                      <% b_left =
                        Float.round(
                          max(DateTime.diff(assigned, min_ts, :second), 0) / span_sec * 100,
                          1
                        ) %>
                      <% b_width =
                        max(
                          Float.round(
                            DateTime.diff(DateTime.utc_now(), assigned, :second) / span_sec * 100,
                            1
                          ),
                          0.3
                        ) %>
                      <div
                        class="absolute top-1.5 h-3 rounded-sm opacity-85 bg-[#5bc0de] animate-pulse"
                        style={"left:#{b_left}%;width:#{b_width}%"}
                        title={"#{job.name}: Building... — #{format_duration(DateTime.diff(DateTime.utc_now(), assigned, :second))}"}
                      >
                      </div>
                    <% end %>
                  </div>

                  <%!-- Duration --%>
                  <span
                    class="shrink-0 text-right text-[10px] text-gray-500 tabular-nums font-mono"
                    style={"width:#{dur_w}px"}
                  >
                    {format_duration(job.duration)}
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp job_gantt_window(jobs) do
    now = DateTime.utc_now()

    starts =
      jobs
      |> Enum.map(& &1[:scheduled_at])
      |> Enum.reject(&is_nil/1)

    ends =
      jobs
      |> Enum.map(fn j ->
        j[:completed_at] || if j[:state] == "Building", do: now
      end)
      |> Enum.reject(&is_nil/1)

    min_ts =
      if starts != [],
        do: Enum.min(starts, DateTime, fn -> now end),
        else: DateTime.add(now, -60, :second)

    max_ts =
      if ends != [],
        do: Enum.max(ends, DateTime, fn -> now end),
        else: now

    span = max(DateTime.diff(max_ts, min_ts, :second), 30)

    pad = round(span * 0.05)
    {DateTime.add(min_ts, -pad, :second), DateTime.add(max_ts, pad, :second), span + 2 * pad}
  end

  defp job_bar_color("Passed"), do: "bg-[#5cb85c]"
  defp job_bar_color("Failed"), do: "bg-[#d9534f]"
  defp job_bar_color("Cancelled"), do: "bg-[#f0ad4e]"
  defp job_bar_color(_), do: "bg-gray-400"

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
              phx-value-tab="timeline"
              class={"px-4 py-3 text-xs font-bold font-mono tracking-wide border-b-2 " <> if @active_tab == "timeline", do: "border-[#2d6ca2] text-[#2d6ca2]", else: "border-transparent text-gray-500 hover:text-gray-700"}
            >
              <i class="fa-solid fa-chart-gantt mr-1.5"></i> Timeline
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
            <button
              phx-click="select_tab"
              phx-value-tab="trends"
              class={"px-4 py-3 text-xs font-bold font-mono tracking-wide border-b-2 " <> if @active_tab == "trends", do: "border-[#2d6ca2] text-[#2d6ca2]", else: "border-transparent text-gray-500 hover:text-gray-700"}
            >
              Trends
            </button>
            <.link
              navigate={~p"/stage-duration/#{@pipeline_name}"}
              class="px-4 py-3 text-xs font-bold font-mono tracking-wide border-b-2 border-transparent text-gray-500 hover:text-gray-700"
            >
              <i class="fa-solid fa-chart-line mr-1.5"></i> Graphs
            </.link>
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
                              <.link
                                navigate={~p"/agents/#{job.agent_uuid}/job_run_history"}
                                class="text-[#2d6ca2] hover:underline font-medium"
                              >
                                {job.agent_hostname}
                              </.link>
                              <div
                                class="text-[10px] text-gray-400 font-mono mt-0.5"
                                title={job.agent_uuid}
                              >
                                {String.slice(job.agent_uuid, 0, 8)}
                                <span :if={job.agent_resources != []} class="ml-1">
                                  <%= for r <- job.agent_resources do %>
                                    <span class="text-[9px] bg-gray-100 text-gray-500 px-1 py-0.5 rounded font-mono">
                                      {r}
                                    </span>
                                  <% end %>
                                </span>
                              </div>
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
              <% "timeline" -> %>
                <.job_gantt
                  jobs={@stage.jobs}
                  pipeline_name={@pipeline_name}
                  pipeline_counter={@pipeline_counter}
                  stage_name={@stage_name}
                  stage_counter={@stage_counter}
                />
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
              <% "trends" -> %>
                <div>
                  <%= if @trends == [] do %>
                    <p class="text-gray-400 text-xs">No historical data for this stage yet.</p>
                  <% else %>
                    <% passed = Enum.count(@trends, &(&1.result == "Passed")) %>
                    <% total = length(@trends) %>
                    <% pass_rate = Float.round(passed / total * 100, 1) %>
                    <% durs = Enum.map(@trends, &(&1.duration || 0)) %>
                    <% avg_dur = if durs != [], do: Float.round(Enum.sum(durs) / length(durs), 1) %>

                    <div class="flex flex-wrap gap-4 mb-5">
                      <div class="bg-gray-50 border border-gray-200 rounded px-4 py-3 flex flex-col gap-0.5 min-w-[110px]">
                        <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">
                          Pass Rate
                        </span>
                        <span class={[
                          "text-lg font-extrabold font-mono",
                          if(pass_rate >= 80,
                            do: "text-green-600",
                            else: if(pass_rate >= 50, do: "text-amber-600", else: "text-red-600")
                          )
                        ]}>
                          {pass_rate}%
                        </span>
                        <span class="text-[10px] text-gray-400">last {total} runs</span>
                      </div>
                      <div class="bg-gray-50 border border-gray-200 rounded px-4 py-3 flex flex-col gap-0.5 min-w-[110px]">
                        <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">
                          Avg Duration
                        </span>
                        <span class="text-lg font-extrabold font-mono text-gray-800">
                          {format_duration(round(avg_dur))}
                        </span>
                        <span class="text-[10px] text-gray-400">per run</span>
                      </div>
                      <div class="bg-gray-50 border border-gray-200 rounded px-4 py-3 flex flex-col gap-0.5 min-w-[110px]">
                        <span class="text-[9px] uppercase font-bold text-gray-400 tracking-wider font-mono">
                          Passed
                        </span>
                        <span class="text-lg font-extrabold font-mono text-green-600">
                          {passed}/{total}
                        </span>
                        <span class="text-[10px] text-gray-400">{total - passed} failed</span>
                      </div>
                    </div>

                    <% max_dur = Enum.max_by(@trends, &(&1.duration || 0)).duration || 1 %>
                    <div class="space-y-2">
                      <%= for t <- @trends do %>
                        <% dur = t.duration || 0 %>
                        <% pct = if max_dur > 0, do: Float.round(dur / max_dur * 100, 1), else: 0 %>
                        <div
                          class="flex items-center gap-2.5 text-xs"
                          title={"##{t.counter}: #{t.result}, #{format_duration(t.duration)}"}
                        >
                          <span class="w-12 shrink-0 text-right tabular-nums font-mono text-gray-500">
                            ##{t.counter}
                          </span>
                          <span class={[
                            "w-14 shrink-0 text-center text-[10px] font-bold px-1.5 py-0.5 rounded uppercase",
                            if(t.result == "Passed",
                              do: "bg-green-100 text-green-700",
                              else: "bg-red-100 text-red-700"
                            )
                          ]}>
                            {t.result}
                          </span>
                          <div class="flex-1 h-5 bg-gray-100 rounded overflow-hidden min-w-0">
                            <% bar_color =
                              if(t.result == "Passed", do: "bg-green-400", else: "bg-red-400") %>
                            <div
                              class={"h-full rounded transition-all #{bar_color}"}
                              style={"width:#{pct}%"}
                            >
                            </div>
                          </div>
                          <span class="w-14 shrink-0 text-right tabular-nums font-semibold text-gray-700">
                            {format_duration(t.duration)}
                          </span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
