defmodule RegionalAffinityWeb.PluginDashboardLive do
  use RegionalAffinityWeb, :live_view
  alias RegionalAffinity.SchedulingDecisions

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(RegionalAffinity.PubSub, "plugin:decisions")

    decisions = SchedulingDecisions.decisions()

    {:ok,
     assign(socket,
       decisions: decisions,
       node: to_string(Node.self()),
       count: length(decisions),
       region_stats: build_region_stats(decisions),
       agent_map: build_agent_map(decisions)
     )}
  end

  @impl true
  def handle_info({:new_decision, entry}, socket) do
    decisions = [entry | socket.assigns.decisions] |> Enum.take(200)

    {:noreply,
     assign(socket,
       decisions: decisions,
       count: length(decisions),
       region_stats: build_region_stats(decisions),
       agent_map: build_agent_map(decisions)
     )}
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp build_region_stats(decisions) do
    decisions
    |> Enum.flat_map(fn d ->
      (d.candidates_detail || [])
      |> Enum.filter(&(&1.uuid == d.preferred))
      |> Enum.map(fn a -> infer_region(a.hostname) end)
      |> Enum.reject(&is_nil/1)
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_r, c} -> -c end)
  end

  defp build_agent_map(decisions) do
    decisions
    |> Enum.flat_map(&(&1.candidates_detail || []))
    |> Enum.uniq_by(& &1.uuid)
    |> Enum.group_by(&infer_region(&1.hostname))
    |> Enum.reject(fn {region, _} -> is_nil(region) end)
    |> Map.new()
  end

  defp infer_region(hostname) when is_binary(hostname) and hostname != "" do
    # Split on dots: "us-east-1.worker.prod" → "us-east-1"
    case String.split(hostname, ".", parts: 2) do
      [region, _] when region != "" -> region
      _ -> nil
    end
  end

  defp infer_region(_), do: nil

  defp state_color("Idle"), do: "badge-success"
  defp state_color("Building"), do: "badge-warning"
  defp state_color("LostContact"), do: "badge-error"
  defp state_color(_), do: "badge-ghost"

  defp bar_color(0), do: "p"
  defp bar_color(1), do: "s"
  defp bar_color(_), do: "a"

  defp bar_height(pct), do: max(8, pct * 0.8)

  defp region_bg(0), do: "bg-primary/10 border-primary/30"
  defp region_bg(1), do: "bg-secondary/10 border-secondary/30"
  defp region_bg(2), do: "bg-accent/10 border-accent/30"
  defp region_bg(_), do: "bg-base-200 border-base-300"

  defp region_badge(0), do: "badge-primary"
  defp region_badge(1), do: "badge-secondary"
  defp region_badge(2), do: "badge-accent"
  defp region_badge(_), do: "badge-neutral"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="max-w-3xl mx-auto px-4 py-8">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold">Scheduling Decisions</h1>
            <p class="text-sm text-base-content/50">
              Regional Affinity Agent Selector · <span class="font-mono">{@node}</span>
            </p>
          </div>
          <div class={[
            "badge badge-lg",
            if(@count > 0, do: "badge-primary", else: "badge-ghost")
          ]}>
            {@count} decisions
          </div>
        </div>

        <%!-- Agent Region Map (only when 2+ regions detected) --%>
        <%= if map_size(@agent_map) >= 2 do %>
          <div class="card bg-base-100 shadow-sm border border-base-300/50 mb-6">
            <div class="card-body p-4">
              <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
                Agent Regions ({map_size(@agent_map)})
              </h2>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <%= for {region, agents} <- @agent_map |> Enum.with_index() do %>
                  <% {region_name, region_agents} = region %>
                  <div class={[
                    "border rounded-lg p-3",
                    region_bg(elem(region, 1))
                  ]}>
                    <div class="flex items-center gap-2 mb-2">
                      <span class={["badge badge-xs", region_badge(elem(region, 1))]}>
                        {region_name}
                      </span>
                      <span class="text-xs text-base-content/40">
                        {length(region_agents)} agents
                      </span>
                    </div>
                    <div class="space-y-1">
                      <%= for agent <- Enum.take(region_agents, 5) do %>
                        <div class="flex items-center gap-2 text-xs">
                          <span class={["badge badge-xs", state_color(agent.state)]}>
                            {agent.state}
                          </span>
                          <span class="font-medium truncate">
                            {if agent.hostname not in [nil, ""], do: agent.hostname, else: String.slice(agent.uuid, 0..11) <> "…"}
                          </span>
                          <%= for r <- Enum.take(agent.resources || [], 2) do %>
                            <span class="text-[10px] opacity-40">{r}</span>
                          <% end %>
                        </div>
                      <% end %>
                      <%= if length(region_agents) > 5 do %>
                        <div class="text-xs text-base-content/30 italic ml-4">
                          +{length(region_agents) - 5} more
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Region Stats (only when 2+ regions with data) --%>
        <%= if length(@region_stats) >= 2 do %>
          <div class="card bg-base-100 shadow-sm border border-base-300/50 mb-6">
            <div class="card-body p-4">
              <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
                Region Preference
              </h2>
              <div class="flex flex-wrap gap-2 items-end">
                <%= for {region, count} <- @region_stats |> Enum.with_index() do %>
                  <% {region_name, region_count} = region %>
                  <% max = @region_stats |> Enum.map(&elem(&1, 1)) |> Enum.max() %>
                  <% pct = if max > 0, do: round(region_count / max * 100), else: 0 %>
                  <div class="flex flex-col items-center gap-1">
                    <span class="text-lg font-bold"><%= region_count %></span>
                    <div
                      class="w-12 rounded-t"
                      style={"height: #{bar_height(pct)}px; background: var(--#{bar_color(count)})"}>
                    </div>
                    <span class={["badge badge-xs", region_badge(count)]}>
                      {region_name}
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Decision Trace Timeline --%>
        <%= if @decisions != [] do %>
          <div class="card bg-base-100 shadow-sm border border-base-300/50 mb-6">
            <div class="card-body p-4">
              <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
                Decision Trace ({@count})
              </h2>
              <div class="overflow-x-auto">
                <div class="flex items-end gap-px" style="height: 60px;">
                  <%= for entry <- @decisions |> Enum.reverse() do %>
                    <% agent_name = if entry.preferred_detail && entry.preferred_detail.hostname not in [nil, ""],
                         do: entry.preferred_detail.hostname,
                         else: "?" %>
                    <% bar_h = cond do
                      entry.preferred_detail && entry.preferred_detail.state == "Building" -> 40
                      entry.preferred_detail && entry.preferred_detail.state == "Idle" -> 30
                      true -> 15
                    end %>
                    <div
                      class={"rounded-t-sm tooltip cursor-pointer #{if bar_h >= 30, do: "bg-success", else: "bg-base-300"}"}
                      style={"width: max(4px, #{max(4, div(800, max(@count, 1)))}px); height: #{bar_h}px;"}
                      data-tip={"#{Calendar.strftime(entry.timestamp, "%H:%M:%S")} → #{agent_name}"}>
                    </div>
                  <% end %>
                </div>
                <div class="flex items-center gap-1 mt-1">
                  <span class="text-[10px] text-base-content/30">
                    {Calendar.strftime(List.last(@decisions).timestamp, "%H:%M")}
                  </span>
                  <div class="flex-1"></div>
                  <span class="text-[10px] text-base-content/30">
                    {Calendar.strftime(List.first(@decisions).timestamp, "%H:%M")}
                  </span>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Decisions --%>
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
                  <%!-- Header: timestamp + node + region --%>
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
                        <% region = infer_region(detail.hostname) %>
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
                            {if detail.hostname not in [nil, ""], do: detail.hostname, else: String.slice(detail.uuid, 0..11) <> "…"}
                          </span>
                          <span class="badge badge-xs badge-outline">{region}</span>
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <%!-- Preferred agent detail --%>
                  <%= if entry.preferred_detail do %>
                    <div class="mt-3 pt-3 border-t border-base-300/50">
                      <p class="text-xs font-medium text-base-content/40 uppercase tracking-wide mb-2">
                        Selected
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
                        <span class="badge badge-xs badge-outline">{infer_region(entry.preferred_detail.hostname)}</span>
                        <%= for r <- entry.preferred_detail.resources do %>
                          <span class="badge badge-xs badge-ghost">{r}</span>
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
