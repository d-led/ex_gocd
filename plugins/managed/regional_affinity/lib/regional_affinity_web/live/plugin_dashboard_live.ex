defmodule RegionalAffinityWeb.PluginDashboardLive do
  use RegionalAffinityWeb, :live_view

  alias RegionalAffinity.SchedulingDecisions

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(RegionalAffinity.PubSub, "plugin:decisions")
    end

    {:ok,
     assign(socket,
       decisions: SchedulingDecisions.decisions(),
       node: to_string(Node.self()),
       count: length(SchedulingDecisions.decisions())
     )}
  end

  @impl true
  def handle_info({:new_decision, entry}, socket) do
    decisions = [entry | socket.assigns.decisions] |> Enum.take(200)
    {:noreply, assign(socket, decisions: decisions, count: length(decisions))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="max-w-5xl mx-auto px-4 py-8">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-8">
          <div>
            <h1 class="text-3xl font-bold text-base-content">Scheduling Decisions</h1>
            <p class="text-sm text-base-content/60 mt-1">
              Real-time agent selection audit
            </p>
          </div>
          <div class="flex items-center gap-4">
            <div class="badge badge-primary badge-lg gap-1">
              <span class="font-mono text-xs">{@node}</span>
            </div>
            <div class="stats shadow">
              <div class="stat py-2 px-4">
                <div class="stat-title text-xs">Decisions</div>
                <div class="stat-value text-lg">{@count}</div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Content --%>
        <%= if Enum.empty?(@decisions) do %>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body items-center text-center py-16">
              <svg
                class="w-16 h-16 text-base-content/20 mb-4"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1"
                  d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
                />
              </svg>
              <h2 class="card-title text-base-content/60">No scheduling decisions yet</h2>
              <p class="text-sm text-base-content/40">
                Trigger a pipeline on ex_gocd to see agent selection in action
              </p>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow-xl overflow-hidden">
            <div class="overflow-x-auto">
              <table class="table table-zebra table-sm">
                <thead>
                  <tr>
                    <th class="w-24">Time</th>
                    <th>Candidates</th>
                    <th>Chosen</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for entry <- @decisions do %>
                    <tr class="hover">
                      <td class="font-mono text-xs text-base-content/60 whitespace-nowrap">
                        {Calendar.strftime(entry.timestamp, "%H:%M:%S")}
                      </td>
                      <td>
                        <div class="flex flex-wrap gap-1">
                          <%= for uuid <- entry.candidates do %>
                            <span class="badge badge-ghost badge-xs font-mono">
                              {String.slice(uuid, 0..7)}
                            </span>
                          <% end %>
                          <%= if Enum.empty?(entry.candidates) do %>
                            <span class="text-base-content/30 text-xs">—</span>
                          <% end %>
                        </div>
                      </td>
                      <td>
                        <%= if entry.chosen do %>
                          <span class="badge badge-success badge-sm gap-1">
                            <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2.5"
                                d="M5 13l4 4L19 7"
                              />
                            </svg>
                            {String.slice(entry.chosen, 0..11)}
                          </span>
                        <% else %>
                          <span class="badge badge-ghost badge-sm">none</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
