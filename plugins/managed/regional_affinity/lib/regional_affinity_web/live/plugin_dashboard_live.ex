defmodule RegionalAffinityWeb.PluginDashboardLive do
  use RegionalAffinityWeb, :live_view
  alias RegionalAffinity.SchedulingDecisions

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(RegionalAffinity.PubSub, "plugin:decisions")

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
      <div class="max-w-3xl mx-auto px-4 py-8">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold">Scheduling Decisions</h1>
            <p class="text-sm text-base-content/50">
              Real-time agent selection · <span class="font-mono">{@node}</span>
            </p>
          </div>
          <div class="badge badge-primary badge-lg">{@count} decisions</div>
        </div>

        <%= if @decisions == [] do %>
          <div class="card bg-base-100 shadow">
            <div class="card-body items-center py-12">
              <p class="text-base-content/40">No decisions yet. Trigger a pipeline build.</p>
            </div>
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for entry <- @decisions do %>
              <div class="card bg-base-100 shadow-sm">
                <div class="card-body py-3 px-4">
                  <div class="flex items-center gap-2 text-xs text-base-content/40 mb-2">
                    <span class="font-mono">{Calendar.strftime(entry.timestamp, "%H:%M:%S")}</span>
                    <span>·</span>
                    <span>{entry.node}</span>
                  </div>
                  <div class="flex flex-wrap items-center gap-2">
                    <%= for uuid <- entry.candidates do %>
                      <% is_pref = uuid == entry[:preferred] %>
                      <span class={[
                        "badge gap-1",
                        if(is_pref, do: "badge-success", else: "badge-ghost")
                      ]}>
                        <%= if is_pref do %>
                          <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2.5"
                            d="M5 13l4 4L19 7"
                          /></svg>
                        <% end %>
                        <span class="font-mono text-xs">{String.slice(uuid, 0..11)}</span>
                      </span>
                    <% end %>
                    <%= if entry[:preferred] not in entry.candidates do %>
                      <span class="badge badge-warning badge-sm gap-1"><svg
                        class="w-3 h-3"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      ><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7"/></svg>{String.slice(
                        entry[:preferred],
                        0..11
                      )}</span>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
