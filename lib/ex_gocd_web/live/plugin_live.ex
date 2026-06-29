defmodule ExGoCDWeb.PluginLive do
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
    with mod when not is_nil(mod) <- ExGoCD.Plugin.Registry.get(:agent_selector),
         node when not is_nil(node) <- ExGoCD.Plugin.Registry.node_for(:agent_selector) do
      {:ok, decisions} = :erpc.call(String.to_atom(node), mod, :decisions, [], 2000)
      decisions
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  defp get_plugin_name do
    case ExGoCD.Plugin.Registry.get(:agent_selector) do
      nil -> "No agent_selector plugin registered"
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
            <p class="text-sm">No scheduling decisions yet.</p>
            <p class="text-xs mt-1">Trigger a pipeline build to see agent selection in action.</p>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-slate-100 bg-slate-50 text-left">
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase w-28">Time</th>
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase">Plugin Node</th>
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase">Candidates</th>
                  <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase">Chosen Agent</th>
                </tr>
              </thead>
              <tbody>
                <%= for entry <- @decisions do %>
                  <tr class="border-b border-slate-50 hover:bg-slate-50/50 transition-colors">
                    <td class="px-4 py-2.5 font-mono text-xs text-slate-500 whitespace-nowrap">
                      {Calendar.strftime(entry.timestamp, "%H:%M:%S")}
                    </td>
                    <td class="px-4 py-2.5 text-xs font-mono text-slate-600">
                      {entry.node}
                    </td>
                    <td class="px-4 py-2.5">
                      <div class="flex flex-wrap gap-1">
                        <%= for uuid <- entry.candidates do %>
                          <span class="inline-flex px-1.5 py-0.5 bg-slate-100 text-slate-600 rounded text-[10px] font-mono">
                            {String.slice(uuid, 0..7)}
                          </span>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-4 py-2.5">
                      <%= if entry.chosen do %>
                        <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">
                          <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                          </svg>
                          {String.slice(entry.chosen, 0..11)}
                        </span>
                      <% else %>
                        <span class="text-xs text-slate-400">none</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
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
end
