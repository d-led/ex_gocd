defmodule ExGoCDWeb.PluginDemoLive do
  use ExGoCDWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(5000, :refresh)
    end

    socket =
      socket
      |> assign(:decisions, fetch_decisions())
      |> assign(:plugin_name, get_plugin_name())
      |> assign(:plugin_status, "active")

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :decisions, fetch_decisions())}
  end

  defp fetch_decisions do
    case ExGoCD.Plugin.Registry.get(:agent_selector) do
      nil ->
        []

      mod ->
        # Call decisions/0 on the plugin node via RPC
        nodes = Node.list()

        case nodes do
          [] ->
            []

          _ ->
            try do
              :rpc.call(hd(nodes), mod, :decisions, [])
            rescue
              _ -> []
            end
        end
    end
  end

  defp get_plugin_name do
    case ExGoCD.Plugin.Registry.get(:agent_selector) do
      nil -> "No plugin registered"
      mod -> "#{inspect(mod)} (AgentSelector)"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-slate-800">Plugin Dashboard</h1>
          <p class="text-sm text-slate-500 mt-1">
            Real-time view of plugin activity across the cluster.
          </p>
        </div>
        <div class="flex items-center gap-4">
          <span class="flex items-center gap-2 text-sm">
            <span class="h-2.5 w-2.5 rounded-full bg-green-500 animate-pulse"></span>
            {@plugin_name}
            <span class="text-slate-400">·</span>
            <span class="text-green-600 font-medium">{@plugin_status}</span>
          </span>
          <span class="text-xs text-slate-400 bg-slate-100 px-2 py-1 rounded">
            /admin/plugins
          </span>
        </div>
      </div>

      <div class="bg-white border border-slate-200 rounded-lg shadow-sm overflow-hidden">
        <div class="px-4 py-3 border-b border-slate-200 bg-slate-50">
          <h2 class="text-sm font-bold text-slate-700 uppercase tracking-wide">
            Scheduling Decisions
            <span class="text-slate-400 font-normal">({length(@decisions)})</span>
          </h2>
        </div>

        <%= if Enum.empty?(@decisions) do %>
          <div class="p-12 text-center text-slate-400">
            <svg
              class="mx-auto h-10 w-10 mb-3 text-slate-300"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="1.5"
                d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
              />
            </svg>
            <p class="text-sm">No scheduling decisions yet.</p>
            <p class="text-xs mt-1">Trigger a pipeline to see the plugin in action.</p>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-slate-100 bg-slate-50 text-left">
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase w-28">Time</th>
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase">Pipeline</th>
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase">Stage / Job</th>
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase">Region</th>
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase">Resources</th>
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase w-16">Agents</th>
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase">Decision</th>
                </tr>
              </thead>
              <tbody>
                <%= for entry <- @decisions do %>
                  <tr class="border-b border-slate-50 hover:bg-slate-50/50 transition-colors">
                    <td class="px-4 py-2.5 font-mono text-xs text-slate-500 whitespace-nowrap">
                      {Calendar.strftime(entry.timestamp, "%H:%M:%S")}
                    </td>
                    <td class="px-4 py-2.5 font-medium text-slate-700">
                      {entry.pipeline}
                    </td>
                    <td class="px-4 py-2.5 text-slate-600">
                      <span class="text-slate-400">{entry.stage}</span>
                      <span class="text-slate-300 mx-1">/</span>
                      <span class="font-medium">{entry.job}</span>
                    </td>
                    <td class="px-4 py-2.5">
                      <span class={"inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium " <> region_class(entry.region)}>
                        {entry.region}
                      </span>
                    </td>
                    <td class="px-4 py-2.5">
                      <div class="flex flex-wrap gap-1">
                        <%= for res <- entry.resources do %>
                          <span class="inline-flex px-1.5 py-0.5 bg-slate-100 text-slate-600 rounded text-[10px] font-medium">
                            {res}
                          </span>
                        <% end %>
                        <%= if Enum.empty?(entry.resources) do %>
                          <span class="text-xs text-slate-300">—</span>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-4 py-2.5 text-center text-slate-600">
                      {entry.agent_count}
                    </td>
                    <td class="px-4 py-2.5">
                      <span class={"inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium " <> decision_class(entry.decision)}>
                        <%= if String.starts_with?(entry.decision, "accepted") do %>
                          <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M5 13l4 4L19 7"
                            />
                          </svg>
                        <% else %>
                          <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M6 18L18 6M6 6l12 12"
                            />
                          </svg>
                        <% end %>
                        {entry.decision}
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp region_class("any"), do: "bg-slate-100 text-slate-500"
  defp region_class(_), do: "bg-blue-50 text-blue-700 border border-blue-200"

  defp decision_class(decision) do
    if String.starts_with?(decision, "accepted"),
      do: "bg-green-50 text-green-700 border border-green-200",
      else: "bg-red-50 text-red-700 border border-red-200"
  end
end
