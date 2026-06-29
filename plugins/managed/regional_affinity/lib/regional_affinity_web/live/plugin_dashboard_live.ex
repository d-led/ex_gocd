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
          <div class={[
            "badge badge-lg",
            if(@count > 0, do: "badge-primary", else: "badge-ghost")
          ]}>
            {@count} decisions
          </div>
        </div>

        <%= if @decisions == [] do %>
          <div class="card bg-base-100 shadow">
            <div class="card-body items-center py-16">
              <svg class="w-12 h-12 text-base-content/20 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"
                  d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
              </svg>
              <p class="text-base-content/40 text-lg">No decisions yet</p>
              <p class="text-base-content/30 text-sm mt-1">
                Trigger a pipeline build to see agent selection in action.
              </p>
            </div>
          </div>
        <% else %>
          <div class="space-y-4">
            <%= for entry <- @decisions do %>
              <div class="card bg-base-100 shadow-sm border border-base-300/50">
                <div class="card-body p-4">
                  <%!-- Header: timestamp + node --%>
                  <div class="flex items-center gap-2 text-xs text-base-content/40 mb-3">
                    <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                    </svg>
                    <span class="font-mono">{Calendar.strftime(entry.timestamp, "%H:%M:%S")}</span>
                    <span>·</span>
                    <span class="font-mono text-xs opacity-60">{entry.node}</span>
                  </div>

                  <%!-- Reason — the WHY --%>
                  <div class={[
                    "px-3 py-2 rounded-md mb-3 text-sm",
                    "bg-accent/10 border border-accent/20"
                  ]}>
                    <span class="font-semibold text-accent">Why: </span>
                    <span class="text-base-content/80">
                      <%= if String.length(entry.reason || "") > 0 do %>
                        {entry.reason}
                      <% else %>
                        <span class="italic text-base-content/30">No reasoning recorded</span>
                      <% end %>
                    </span>
                  </div>

                  <%!-- Candidate agents --%>
                  <div class="space-y-1.5">
                    <p class="text-xs font-medium text-base-content/40 uppercase tracking-wide">
                      Candidates ({length(entry.candidates)})
                    </p>
                    <div class="flex flex-wrap gap-2">
                      <%= for detail <- entry.candidates_detail do %>
                        <% is_pref = detail.uuid == entry.preferred %>
                        <% host = detail.hostname not in [nil, ""] %>
                        <div class={[
                          "flex items-center gap-1.5 px-2.5 py-1.5 rounded-md text-xs border",
                          if(is_pref,
                            do: "bg-success/10 border-success/30 text-success",
                            else: "bg-base-200 border-base-300 text-base-content/60"
                          )
                        ]}>
                          <%= if is_pref do %>
                            <svg class="w-3.5 h-3.5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7"/>
                            </svg>
                          <% end %>
                          <span class="font-semibold">
                            {if host, do: detail.hostname, else: String.slice(detail.uuid, 0..11) <> "…"}
                          </span>
                          <%= if host do %>
                            <span class="text-[10px] opacity-50 font-mono">
                              {String.slice(detail.uuid, 0, 8)}
                            </span>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <%!-- Preferred agent detail --%>
                  <%= if entry.preferred_detail do %>
                    <div class="mt-3 pt-3 border-t border-base-300/50">
                      <p class="text-xs font-medium text-base-content/40 uppercase tracking-wide mb-2">
                        Preferred
                      </p>
                      <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-base-content/70">
                        <span class="font-semibold text-success">
                          <%= if entry.preferred_detail.hostname not in [nil, ""] do %>
                            {entry.preferred_detail.hostname}
                          <% else %>
                            {String.slice(entry.preferred_detail.uuid, 0..11)}…
                          <% end %>
                        </span>
                        <span class="font-mono text-[10px] opacity-50">
                          {String.slice(entry.preferred_detail.uuid, 0, 8)}
                        </span>
                        <span class="badge badge-xs badge-outline">{entry.preferred_detail.state}</span>
                        <%= for r <- entry.preferred_detail.resources do %>
                          <span class="badge badge-xs badge-ghost">{r}</span>
                        <% end %>
                        <%= for e <- entry.preferred_detail.environments do %>
                          <span class="badge badge-xs badge-outline badge-info">{e}</span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
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
