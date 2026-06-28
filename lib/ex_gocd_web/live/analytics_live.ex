defmodule ExGoCDWeb.AnalyticsLive do
  @moduledoc """
  Built-in CI Analytics dashboard (parity with GoCD Analytics Plugin).

  Tabs: Global, Pipelines, Agents, VSM Trends.
  Accessible at /analytics without external tools.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.Analytics
  alias Contex.{Dataset, Plot, BarChart, LinePlot}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Analytics")
     |> assign(:active_tab, "global")
     |> assign(:top_pipelines, [])
     |> assign(:top_agents, [])
     |> assign(:all_pipeline_stats, [])
     |> assign(:selected_pipeline, nil)
     |> assign(:pipeline_detail, nil)
     |> assign(:agent_stats, [])
     |> assign(:snapshot_trends, [])
     |> assign(:latest_snapshot, nil)
     |> assign(:vsm_data, [])
     |> load_global()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = params["tab"] || "global"
    pipeline = params["pipeline"]
    socket = socket |> assign(:active_tab, tab) |> assign(:selected_pipeline, pipeline)

    socket =
      case tab do
        "global" -> load_global(socket)
        "pipelines" -> load_pipelines(socket)
        "pipeline_detail" -> load_pipeline_detail(socket, pipeline)
        "agents" -> load_agents(socket)
        "vsm" -> load_vsm(socket, pipeline)
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/analytics/#{tab}")}
  end

  @impl true
  def handle_event("select_pipeline", %{"name" => name}, socket) do
    {:noreply, push_patch(socket, to: ~p"/analytics/pipeline_detail?pipeline=#{name}")}
  end

  defp load_global(socket) do
    socket
    |> assign(:top_pipelines, Analytics.top_pipelines_by_wait_time(7, 10))
    |> assign(
      :top_agents,
      Analytics.enriched_agent_analytics(7)
      |> Enum.sort_by(& &1.total_jobs, :desc)
      |> Enum.take(10)
    )
    |> assign(:all_pipeline_stats, Analytics.all_pipelines_analytics(30))
  end

  defp load_pipelines(socket),
    do: assign(socket, :all_pipeline_stats, Analytics.all_pipelines_analytics(30))

  defp load_pipeline_detail(socket, nil), do: assign(socket, :pipeline_detail, nil)

  defp load_pipeline_detail(socket, name),
    do: assign(socket, :pipeline_detail, Analytics.pipeline_analytics(name, 30))

  defp load_agents(socket) do
    socket
    |> assign(:agent_stats, Analytics.enriched_agent_analytics(7))
    |> assign(:snapshot_trends, Analytics.agent_snapshot_trends(24))
    |> assign(:latest_snapshot, Analytics.latest_agent_snapshot())
  end

  defp load_vsm(socket, nil), do: assign(socket, :vsm_data, [])
  defp load_vsm(socket, name), do: assign(socket, :vsm_data, Analytics.vsm_trends(name, 30))

  # ---------------------------------------------------------------------------
  # Function Components
  # ---------------------------------------------------------------------------

  def global_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
        <div class="px-4 py-3 border-b border-gray-100">
          <h2 class="text-lg font-semibold text-gray-800">Top Pipelines by Wait Time (7d avg)</h2>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="bg-gray-50 text-gray-600">
              <tr>
                <th class="text-left px-4 py-2 font-medium">Pipeline</th>
                <th class="text-right px-4 py-2 font-medium">Avg Wait</th>
              </tr>
            </thead>
            <tbody>
              <%= if Enum.empty?(@top_pipelines) do %>
                <tr>
                  <td colspan="2" class="px-4 py-6 text-center text-gray-400">No data yet</td>
                </tr>
              <% else %>
                <%= for item <- @top_pipelines do %>
                  <tr
                    class="border-t border-gray-50 hover:bg-gray-50 cursor-pointer"
                    phx-click="select_pipeline"
                    phx-value-name={item.name}
                  >
                    <td class="px-4 py-2.5 font-medium text-gray-800">
                      <a
                        href="#"
                        onclick="event.preventDefault()"
                        class="text-blue-600 hover:underline"
                      >
                        {item.name}
                      </a>
                    </td>
                    <td class={"px-4 py-2.5 text-right tabular-nums #{wait_color(item.avg_wait_sec)}"}>
                      {fmt_sec(item.avg_wait_sec)}
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
        <div class="px-4 py-3 border-b border-gray-100">
          <h2 class="text-lg font-semibold text-gray-800">Top Agents by Jobs Run (7d)</h2>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="bg-gray-50 text-gray-600">
              <tr>
                <th class="text-left px-4 py-2 font-medium">Agent</th>
                <th class="text-right px-4 py-2 font-medium">Jobs</th>
                <th class="text-right px-4 py-2 font-medium">Passed</th>
                <th class="text-right px-4 py-2 font-medium">Failed</th>
              </tr>
            </thead>
            <tbody>
              <%= if Enum.empty?(@top_agents) do %>
                <tr>
                  <td colspan="4" class="px-4 py-6 text-center text-gray-400">No data yet</td>
                </tr>
              <% else %>
                <%= for a <- @top_agents do %>
                  <tr class="border-t border-gray-50">
                    <td class="px-4 py-2.5 font-medium text-gray-800" title={a.agent_uuid}>
                      {a.hostname}
                      <span class="ml-1.5"><.agent_type_badge type={a.agent_type} /></span>
                    </td>
                    <td class="px-4 py-2.5 text-right tabular-nums font-medium">{a.total_jobs}</td>
                    <td class="px-4 py-2.5 text-right tabular-nums text-green-600">{a.completed}</td>
                    <td class="px-4 py-2.5 text-right tabular-nums text-red-600">{a.failed}</td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <.global_charts all_stats={@all_stats} top_agents={@top_agents} />

    <div class="mt-6 bg-white rounded-lg border border-gray-200 shadow-sm">
      <div class="px-4 py-3 border-b border-gray-100">
        <h2 class="text-lg font-semibold text-gray-800">All Pipelines (30d)</h2>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="bg-gray-50 text-gray-600">
            <tr>
              <th class="text-left px-4 py-2 font-medium">Pipeline</th>
              <th class="text-right px-4 py-2 font-medium">Runs (7d)</th>
              <th class="text-left px-4 py-2 font-medium">Latest</th>
            </tr>
          </thead>
          <tbody>
            <%= for stat <- @all_stats do %>
              <tr
                class="border-t border-gray-50 hover:bg-gray-50 cursor-pointer"
                phx-click="select_pipeline"
                phx-value-name={stat.name}
              >
                <td class="px-4 py-2.5 font-medium">
                  <a href="#" onclick="event.preventDefault()" class="text-blue-600 hover:underline">
                    {stat.name}
                  </a>
                </td>
                <td class="px-4 py-2.5 text-right tabular-nums">{stat.run_count}</td>
                <td class="px-4 py-2.5">
                  <span class={[
                    "inline-flex px-2 py-0.5 rounded-full text-xs font-medium",
                    status_bg(stat.latest_status),
                    status_color(stat.latest_status)
                  ]}>
                    {stat.latest_status}
                  </span>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp global_charts(assigns) do
    ~H"""
    <div :if={@all_stats != []} class="mt-6 grid grid-cols-1 lg:grid-cols-2 gap-6">
      <div class="bg-white rounded-lg border border-gray-200 shadow-sm p-4">
        <h3 class="text-sm font-semibold text-gray-700 mb-3">Pipeline Run Counts (30d)</h3>
        {run_count_chart(@all_stats)}
      </div>
      <div class="bg-white rounded-lg border border-gray-200 shadow-sm p-4">
        <h3 class="text-sm font-semibold text-gray-700 mb-3">Agent Jobs (7d)</h3>
        <.agent_top_bar agents={@top_agents} />
      </div>
    </div>
    """
  end

  defp run_count_chart(stats) do
    data = for s <- stats, do: [s.name, s.run_count]
    dataset = Dataset.new(data, ["Pipeline", "Runs"])
    chart = BarChart.new(dataset, type: :stacked)
    plot = Plot.new(500, 240, chart)
    Plot.to_svg(plot)
  end

  defp agent_top_bar(assigns) do
    agents = assigns.agents |> Enum.sort_by(& &1.total_jobs, :desc) |> Enum.take(8)
    max_jobs = if agents != [], do: Enum.max_by(agents, & &1.total_jobs).total_jobs, else: 1
    assigns = assign(assigns, :agents_list, agents)
    assigns = assign(assigns, :max_jobs, max_jobs)

    ~H"""
    <div class="space-y-2">
      <%= for a <- @agents_list do %>
        <% pct = if @max_jobs > 0, do: Float.round(a.total_jobs / @max_jobs * 100, 1), else: 0 %>
        <div
          class="flex items-center gap-2.5 text-xs group"
          title={"#{a.agent_uuid}\nType: #{a.agent_type}\nJobs: #{a.total_jobs} · Passed: #{a.completed} · Failed: #{a.failed}"}
        >
          <span class="w-28 shrink-0 truncate text-gray-700 font-medium">{a.hostname}</span>
          <.agent_type_badge type={a.agent_type} />
          <div class="flex-1 h-5 bg-gray-100 rounded overflow-hidden min-w-0">
            <div class="h-full bg-blue-500 rounded transition-all" style={"width:#{pct}%"}></div>
          </div>
          <span class="w-12 shrink-0 text-right tabular-nums font-semibold text-gray-700">
            {a.total_jobs}
          </span>
          <span class="w-12 shrink-0 text-right tabular-nums text-[11px] text-gray-400">{pct}%</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp build_duration_chart(runs) do
    sorted = Enum.sort_by(runs, & &1.counter, :asc)
    data = for r <- sorted, do: [r.counter, r.build_time_sec || 0]
    dataset = Dataset.new(data, ["Run #", "Duration (sec)"])
    chart = LinePlot.new(dataset)
    plot = Plot.new(500, 240, chart)
    Plot.to_svg(plot)
  end

  def pipelines_tab(assigns) do
    ~H"""
    <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
      <div class="px-4 py-3 border-b border-gray-100 flex justify-between items-center">
        <h2 class="text-lg font-semibold text-gray-800">Pipeline Analytics</h2>
        <span class="text-xs text-gray-400">Click for detailed analytics</span>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="bg-gray-50 text-gray-600">
            <tr>
              <th class="text-left px-4 py-2 font-medium">Pipeline</th>
              <th class="text-right px-4 py-2 font-medium">Runs (30d)</th>
              <th class="text-left px-4 py-2 font-medium">Latest</th>
            </tr>
          </thead>
          <tbody>
            <%= for stat <- @stats do %>
              <tr
                class="border-t border-gray-50 hover:bg-gray-50 cursor-pointer"
                phx-click="select_pipeline"
                phx-value-name={stat.name}
              >
                <td class="px-4 py-2.5 font-medium">
                  <span class="text-blue-600 hover:underline">{stat.name}</span>
                </td>
                <td class="px-4 py-2.5 text-right tabular-nums">{stat.run_count}</td>
                <td class="px-4 py-2.5">
                  <span class={[
                    "inline-flex px-2 py-0.5 rounded-full text-xs font-medium",
                    status_bg(stat.latest_status),
                    status_color(stat.latest_status)
                  ]}>
                    {stat.latest_status}
                  </span>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  def pipeline_detail_tab(assigns) do
    ~H"""
    <%= if is_nil(@detail) do %>
      <div class="bg-white rounded-lg border border-gray-200 shadow-sm p-8 text-center">
        <p class="text-gray-400">Select a pipeline for detailed analytics.</p>
      </div>
    <% else %>
      <div class="space-y-6">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div class="bg-white rounded-lg border border-gray-200 shadow-sm p-4">
            <p class="text-xs text-gray-500 uppercase tracking-wide">Runs (30d)</p>
            <p class="text-2xl font-bold text-gray-900 mt-1">{@detail.run_count}</p>
          </div>
          <div class="bg-white rounded-lg border border-gray-200 shadow-sm p-4">
            <p class="text-xs text-gray-500 uppercase tracking-wide">Pass Rate</p>
            <p class={"text-2xl font-bold mt-1 #{pass_rate_color(@detail.pass_rate)}"}>
              {fmt_pct(@detail.pass_rate)}
            </p>
          </div>
          <div class="bg-white rounded-lg border border-gray-200 shadow-sm p-4">
            <p class="text-xs text-gray-500 uppercase tracking-wide">MTTR</p>
            <p class="text-2xl font-bold text-gray-900 mt-1">{fmt_sec(@detail.mttr_sec)}</p>
          </div>
          <div class="bg-white rounded-lg border border-gray-200 shadow-sm p-4">
            <p class="text-xs text-gray-500 uppercase tracking-wide">Avg Wait Time</p>
            <p class={"text-2xl font-bold mt-1 #{wait_color(@detail.avg_wait_time_sec)}"}>
              {fmt_sec(@detail.avg_wait_time_sec)}
            </p>
          </div>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="bg-white rounded-lg border border-gray-200 shadow-sm p-4">
            <p class="text-sm font-semibold text-gray-700 mb-1">Avg Build Time</p>
            <p class="text-3xl font-bold text-gray-900">{fmt_sec(@detail.avg_build_time_sec)}</p>
          </div>
        </div>

        <div
          :if={@detail.recent_runs != []}
          class="bg-white rounded-lg border border-gray-200 shadow-sm p-4"
        >
          <h3 class="text-sm font-semibold text-gray-700 mb-3">Build Duration Trend</h3>
          {build_duration_chart(@detail.recent_runs)}
        </div>

        <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
          <div class="px-4 py-3 border-b border-gray-100">
            <h3 class="font-semibold text-gray-800">Recent Runs</h3>
          </div>
          <div class="overflow-x-auto max-h-96 overflow-y-auto">
            <table class="w-full text-sm">
              <thead class="bg-gray-50 text-gray-600 sticky top-0">
                <tr>
                  <th class="text-left px-4 py-2 font-medium">#</th>
                  <th class="text-left px-4 py-2 font-medium">Label</th>
                  <th class="text-left px-4 py-2 font-medium">Status</th>
                  <th class="text-right px-4 py-2 font-medium">Build Time</th>
                  <th class="text-left px-4 py-2 font-medium">Triggered</th>
                </tr>
              </thead>
              <tbody>
                <%= for run <- @detail.recent_runs do %>
                  <tr class="border-t border-gray-50">
                    <td class="px-4 py-2 tabular-nums font-medium">{run.counter}</td>
                    <td class="px-4 py-2 text-gray-700">{run.label}</td>
                    <td class="px-4 py-2">
                      <span class={[
                        "inline-flex px-2 py-0.5 rounded-full text-xs font-medium",
                        status_bg(run.status),
                        status_color(run.status)
                      ]}>
                        {run.status}
                      </span>
                    </td>
                    <td class="px-4 py-2 text-right tabular-nums">{fmt_sec(run.build_time_sec)}</td>
                    <td class="px-4 py-2 text-xs text-gray-500">
                      {if run.triggered_at, do: Calendar.strftime(run.triggered_at, "%Y-%m-%d %H:%M")}
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  def agents_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Snapshot summary cards --%>
      <%= if @latest_snapshot do %>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div class="bg-white rounded-lg border border-gray-200 shadow-sm p-3">
            <p class="text-xs text-gray-500 uppercase tracking-wide">Total</p>
            <p class="text-xl font-bold text-gray-900 mt-0.5">{@latest_snapshot.total}</p>
          </div>
          <div class="bg-white rounded-lg border border-green-200 shadow-sm p-3">
            <p class="text-xs text-gray-500 uppercase tracking-wide">Idle</p>
            <p class="text-xl font-bold text-green-700 mt-0.5">{@latest_snapshot.idle}</p>
          </div>
          <div class="bg-white rounded-lg border border-blue-200 shadow-sm p-3">
            <p class="text-xs text-gray-500 uppercase tracking-wide">Building</p>
            <p class="text-xl font-bold text-blue-700 mt-0.5">{@latest_snapshot.building}</p>
          </div>
          <div class="bg-white rounded-lg border border-purple-200 shadow-sm p-3">
            <p class="text-xs text-gray-500 uppercase tracking-wide">Elastic</p>
            <p class="text-xl font-bold text-purple-700 mt-0.5">{@latest_snapshot.elastic}</p>
          </div>
        </div>
      <% end %>

      <%!-- Agent utilization table --%>
      <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
        <div class="px-4 py-3 border-b border-gray-100">
          <h2 class="text-lg font-semibold text-gray-800">Agent Utilization (7d)</h2>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="bg-gray-50 text-gray-600">
              <tr>
                <th class="text-left px-4 py-2 font-medium">Agent</th>
                <th class="text-left px-4 py-2 font-medium">Type</th>
                <th class="text-right px-4 py-2 font-medium">Jobs</th>
                <th class="text-right px-4 py-2 font-medium">Passed</th>
                <th class="text-right px-4 py-2 font-medium">Failed</th>
              </tr>
            </thead>
            <tbody>
              <%= if Enum.empty?(@stats) do %>
                <tr>
                  <td colspan="5" class="px-4 py-6 text-center text-gray-400">
                    No agent job data yet
                  </td>
                </tr>
              <% else %>
                <%= for a <- Enum.sort_by(@stats, & &1.total_jobs, :desc) do %>
                  <tr class="border-t border-gray-50">
                    <td class="px-4 py-2.5 font-medium text-gray-800" title={a.agent_uuid}>
                      {a.hostname}
                    </td>
                    <td class="px-4 py-2.5">
                      <.agent_type_badge type={a.agent_type} />
                    </td>
                    <td class="px-4 py-2.5 text-right tabular-nums font-medium">{a.total_jobs}</td>
                    <td class="px-4 py-2.5 text-right tabular-nums text-green-600">{a.completed}</td>
                    <td class="px-4 py-2.5 text-right tabular-nums text-red-600">{a.failed}</td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <.agent_jobs_chart stats={@stats} />
    </div>
    """
  end

  defp agent_type_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex px-1.5 py-0.5 rounded-full text-[11px] font-medium",
      case @type do
        "regular" -> "bg-gray-100 text-gray-600"
        "docker" -> "bg-blue-100 text-blue-700"
        "elastic-docker" -> "bg-purple-100 text-purple-700"
        "elastic-k8s" -> "bg-indigo-100 text-indigo-700"
        "k8s-elastic" -> "bg-indigo-100 text-indigo-700"
        "k8s-elastic" -> "bg-indigo-100 text-indigo-700"
        _ -> "bg-gray-100 text-gray-600"
      end
    ]}>
      {String.replace(@type, "-", " ")}
    </span>
    """
  end

  defp agent_jobs_chart(assigns) do
    stats = assigns.stats
    agents = stats |> Enum.sort_by(& &1.total_jobs, :desc) |> Enum.take(15)
    max_jobs = if agents != [], do: Enum.max_by(agents, & &1.total_jobs).total_jobs, else: 1
    assigns = assign(assigns, :chart_agents, agents)
    assigns = assign(assigns, :chart_max, max_jobs)

    ~H"""
    <div :if={@stats != []} class="mt-6 bg-white rounded-lg border border-gray-200 shadow-sm p-4">
      <h3 class="text-sm font-semibold text-gray-700 mb-3">Job Outcomes by Agent</h3>
      <div class="space-y-1.5">
        <%= for a <- @chart_agents do %>
          <% pass_pct =
            if a.total_jobs > 0, do: Float.round(a.completed / a.total_jobs * 100, 0), else: 0 %>
          <div
            class="flex items-center gap-2.5 text-xs"
            title={"#{a.agent_uuid}\nType: #{a.agent_type}\nPassed: #{a.completed}  Failed: #{a.failed}  Cancelled: #{a.cancelled}"}
          >
            <span class="w-28 shrink-0 truncate text-gray-700 font-medium">{a.hostname}</span>
            <.agent_type_badge type={a.agent_type} />
            <div class="flex-1 h-5 bg-gray-100 rounded overflow-hidden flex min-w-0">
              <div
                class="h-full bg-green-500"
                style={"width:#{Float.round(a.completed / @chart_max * 100, 1)}%"}
              >
              </div>
              <div
                class="h-full bg-red-400"
                style={"width:#{Float.round(a.failed / @chart_max * 100, 1)}%"}
              >
              </div>
            </div>
            <span class="w-12 shrink-0 text-right tabular-nums font-semibold text-gray-700">
              {a.total_jobs}
            </span>
            <span class="w-10 shrink-0 text-right tabular-nums text-[11px] text-green-600">
              {pass_pct}%
            </span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def vsm_tab(assigns) do
    ~H"""
    <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
      <div class="px-4 py-3 border-b border-gray-100">
        <h2 class="text-lg font-semibold text-gray-800">
          VSM Trends{if @pipeline_name, do: " • #{@pipeline_name}"}
        </h2>
        <p class="text-xs text-gray-400 mt-1">Last 30 pipeline runs with stage breakdowns</p>
      </div>
      <%= if Enum.empty?(@data) do %>
        <div class="p-8 text-center text-gray-400">
          Select a pipeline from the Pipelines tab to view VSM trends.
        </div>
      <% else %>
        <div class="overflow-x-auto max-h-[600px] overflow-y-auto">
          <table class="w-full text-sm">
            <thead class="bg-gray-50 text-gray-600 sticky top-0">
              <tr>
                <th class="text-left px-4 py-2 font-medium">Run #</th>
                <th class="text-right px-4 py-2 font-medium">Duration</th>
                <th class="text-right px-4 py-2 font-medium">Stages</th>
                <th class="text-left px-4 py-2 font-medium">Stage Breakdown</th>
              </tr>
            </thead>
            <tbody>
              <%= for run <- @data do %>
                <tr class="border-t border-gray-50">
                  <td class="px-4 py-2 font-medium tabular-nums">
                    {run.counter} <span class="text-xs text-gray-400 ml-1">{run.label}</span>
                  </td>
                  <td class="px-4 py-2 text-right tabular-nums">{fmt_sec(run.total_duration_sec)}</td>
                  <td class="px-4 py-2 text-right tabular-nums">{run.stage_count}</td>
                  <td class="px-4 py-2">
                    <div class="flex flex-wrap gap-1">
                      <%= for stage <- run.stages do %>
                        <span
                          class={[
                            "inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-xs font-medium",
                            status_bg(stage.result),
                            status_color(stage.result)
                          ]}
                          title={"#{stage.name}: #{fmt_sec(stage.duration_sec)}"}
                        >
                          {stage.name} {fmt_sec(stage.duration_sec)}
                        </span>
                      <% end %>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>

    <.vsm_chart data={@data} pipeline_name={@pipeline_name} />
    """
  end

  defp vsm_chart(assigns) do
    ~H"""
    <div :if={@data != []} class="mt-6 bg-white rounded-lg border border-gray-200 shadow-sm p-4">
      <h3 class="text-sm font-semibold text-gray-700 mb-3">Cycle Time Trend (30 runs)</h3>
      {vsm_duration_chart(@data)}
    </div>
    """
  end

  defp vsm_duration_chart(data) do
    sorted = Enum.sort_by(data, & &1.counter, :asc)
    rows = for r <- sorted, do: [r.counter, r.total_duration_sec || 0]
    dataset = Dataset.new(rows, ["Run #", "Duration (sec)"])
    chart = LinePlot.new(dataset)
    plot = Plot.new(500, 240, chart)
    Plot.to_svg(plot)
  end

  # Helpers
  def fmt_sec(nil), do: "—"
  def fmt_sec(sec) when sec < 60, do: "#{Float.round(sec, 1)}s"
  def fmt_sec(sec) when sec < 3600, do: "#{Float.round(sec / 60, 1)}m"
  def fmt_sec(sec), do: "#{Float.round(sec / 3600, 1)}h"
  def fmt_pct(nil), do: "—"
  def fmt_pct(pct), do: "#{pct}%"
  def status_color("Passed"), do: "text-green-600"
  def status_color("Failed"), do: "text-red-600"
  def status_color("Building"), do: "text-yellow-600"
  def status_color(_), do: "text-gray-500"
  def status_bg("Passed"), do: "bg-green-100"
  def status_bg("Failed"), do: "bg-red-100"
  def status_bg("Building"), do: "bg-yellow-100"
  def status_bg(_), do: "bg-gray-100"
  def wait_color(nil), do: "text-gray-700"
  def wait_color(sec) when sec > 120, do: "text-red-600"
  def wait_color(_), do: "text-gray-700"
  def pass_rate_color(nil), do: "text-gray-900"
  def pass_rate_color(pct) when pct >= 80, do: "text-green-600"
  def pass_rate_color(_), do: "text-red-600"
end
