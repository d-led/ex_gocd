defmodule ExGoCDWeb.AnalyticsLive do
  @moduledoc """
  Built-in CI Analytics dashboard (parity with GoCD Analytics Plugin).

  Tabs: Global, Pipelines, Agents, VSM Trends.
  Accessible at /analytics without external tools.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.Analytics

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
    |> assign(:top_agents, Analytics.top_agents_by_utilization(7, 10))
    |> assign(:all_pipeline_stats, Analytics.all_pipelines_analytics(30))
  end

  defp load_pipelines(socket),
    do: assign(socket, :all_pipeline_stats, Analytics.all_pipelines_analytics(30))

  defp load_pipeline_detail(socket, nil), do: assign(socket, :pipeline_detail, nil)

  defp load_pipeline_detail(socket, name),
    do: assign(socket, :pipeline_detail, Analytics.pipeline_analytics(name, 30))

  defp load_agents(socket), do: assign(socket, :agent_stats, Analytics.agent_analytics(7))
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
                    <td
                      class="px-4 py-2.5 font-mono text-xs text-gray-700 truncate max-w-[120px]"
                      title={a.agent_uuid}
                    >
                      {String.slice(a.agent_uuid, 0, 12) <> "…"}
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
    <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
      <div class="px-4 py-3 border-b border-gray-100">
        <h2 class="text-lg font-semibold text-gray-800">Agent Utilization (7d)</h2>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="bg-gray-50 text-gray-600">
            <tr>
              <th class="text-left px-4 py-2 font-medium">Agent UUID</th>
              <th class="text-right px-4 py-2 font-medium">Total Jobs</th>
              <th class="text-right px-4 py-2 font-medium">Completed</th>
              <th class="text-right px-4 py-2 font-medium">Failed</th>
              <th class="text-right px-4 py-2 font-medium">Cancelled</th>
            </tr>
          </thead>
          <tbody>
            <%= if Enum.empty?(@stats) do %>
              <tr>
                <td colspan="5" class="px-4 py-6 text-center text-gray-400">No agent job data yet</td>
              </tr>
            <% else %>
              <%= for a <- Enum.sort_by(@stats, & &1.total_jobs, :desc) do %>
                <tr class="border-t border-gray-50">
                  <td
                    class="px-4 py-2.5 font-mono text-xs text-gray-700 truncate max-w-[180px]"
                    title={a.agent_uuid}
                  >
                    {a.agent_uuid}
                  </td>
                  <td class="px-4 py-2.5 text-right tabular-nums font-medium">{a.total_jobs}</td>
                  <td class="px-4 py-2.5 text-right tabular-nums text-green-600">{a.completed}</td>
                  <td class="px-4 py-2.5 text-right tabular-nums text-red-600">{a.failed}</td>
                  <td class="px-4 py-2.5 text-right tabular-nums text-yellow-600">{a.cancelled}</td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
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
    """
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
