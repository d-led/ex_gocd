defmodule RegionalAffinityWeb.PluginDashboardLive do
  use RegionalAffinityWeb, :live_view

  alias RegionalAffinity.SchedulingDecisions

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(3000, :refresh)

    {:ok,
     assign(socket, decisions: SchedulingDecisions.decisions(), node: to_string(Node.self()))}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, decisions: SchedulingDecisions.decisions())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold text-slate-800 mb-2">Scheduling Decisions</h1>
      <p class="text-sm text-slate-500 mb-6">
        Real-time agent selection audit. Node: <span class="font-mono text-slate-700">{@node}</span>
      </p>

      <%= if Enum.empty?(@decisions) do %>
        <div class="p-12 text-center text-slate-400 bg-white border rounded-lg">
          <p class="text-sm">No scheduling decisions yet.</p>
          <p class="text-xs mt-1">
            Trigger a pipeline build on ex_gocd to see agent selection in action.
          </p>
        </div>
      <% else %>
        <div class="bg-white border border-slate-200 rounded-lg shadow-sm overflow-hidden">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-slate-100 bg-slate-50 text-left">
                <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase w-28">Time</th>
                <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase">Candidates</th>
                <th class="px-4 py-2 text-xs font-medium text-slate-500 uppercase">Chosen Agent</th>
              </tr>
            </thead>
            <tbody>
              <%= for entry <- @decisions do %>
                <tr class="border-b border-slate-50 hover:bg-slate-50/50">
                  <td class="px-4 py-2.5 font-mono text-xs text-slate-500 whitespace-nowrap">
                    {Calendar.strftime(entry.timestamp, "%H:%M:%S")}
                  </td>
                  <td class="px-4 py-2.5">
                    <div class="flex flex-wrap gap-1">
                      <%= for uuid <- entry.candidates do %>
                        <span class="px-1.5 py-0.5 bg-slate-100 text-slate-600 rounded text-[10px] font-mono">
                          {String.slice(uuid, 0..7)}
                        </span>
                      <% end %>
                    </div>
                  </td>
                  <td class="px-4 py-2.5">
                    <%= if entry.chosen do %>
                      <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">
                        ✓ {String.slice(entry.chosen, 0..11)}
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
    """
  end
end
