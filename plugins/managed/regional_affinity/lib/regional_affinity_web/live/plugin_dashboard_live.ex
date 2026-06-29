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
    <div style="min-height:100vh;background:#f3f4f6;font-family:system-ui,sans-serif">
      <div style="max-width:64rem;margin:0 auto;padding:2rem 1rem">
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:2rem">
          <div>
            <h1 style="font-size:1.875rem;font-weight:700;color:#1f2937;margin:0">
              Scheduling Decisions
            </h1><p style="font-size:.875rem;color:#6b7280;margin-top:.25rem">
              Real-time agent selection audit
            </p>
          </div>
          <div style="display:flex;align-items:center;gap:1rem">
            <span style="padding:.25rem .75rem;background:#7c3aed;color:#fff;border-radius:9999px;font-size:.75rem;font-family:monospace">{@node}</span>
            <div style="background:#fff;border-radius:.5rem;box-shadow:0 1px 3px rgba(0,0,0,.1);padding:.5rem 1rem;text-align:center">
              <div style="font-size:.625rem;color:#9ca3af;text-transform:uppercase">Decisions</div><div style="font-size:1.25rem;font-weight:700;color:#1f2937">
                {@count}
              </div>
            </div>
          </div>
        </div>

        <%= if @decisions == [] do %>
          <div style="background:#fff;border-radius:.5rem;box-shadow:0 1px 3px rgba(0,0,0,.1);padding:4rem 2rem;text-align:center">
            <svg
              style="width:3rem;height:3rem;color:#d1d5db;margin-bottom:1rem"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            ><path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1"
              d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
            /></svg>
            <h2 style="font-size:1.125rem;color:#9ca3af;margin:0">No scheduling decisions yet</h2>
            <p style="font-size:.875rem;color:#d1d5db;margin-top:.5rem">
              Trigger a pipeline on ex_gocd to see agent selection
            </p>
          </div>
        <% else %>
          <div style="background:#fff;border-radius:.5rem;box-shadow:0 1px 3px rgba(0,0,0,.1);overflow:hidden">
            <table style="width:100%;font-size:.875rem;border-collapse:collapse">
              <thead>
                <tr style="background:#f9fafb">
                  <th style="padding:.5rem 1rem;font-size:.625rem;font-weight:600;color:#6b7280;text-transform:uppercase;text-align:left;width:6rem">
                    Time
                  </th><th style="padding:.5rem 1rem;font-size:.625rem;font-weight:600;color:#6b7280;text-transform:uppercase;text-align:left">
                    Candidates
                  </th><th style="padding:.5rem 1rem;font-size:.625rem;font-weight:600;color:#6b7280;text-transform:uppercase;text-align:left">
                    Chosen
                  </th>
                </tr>
              </thead>
              <tbody>
                <%= for entry <- @decisions do %>
                  <tr style="border-top:1px solid #f3f4f6">
                    <td style="padding:.625rem 1rem;font-family:monospace;font-size:.75rem;color:#6b7280;white-space:nowrap">
                      {Calendar.strftime(entry.timestamp, "%H:%M:%S")}
                    </td>
                    <td style="padding:.625rem 1rem">
                      <div style="display:flex;flex-wrap:wrap;gap:.25rem">
                        <%= for uuid <- entry.candidates do %>
                          <span style="padding:.125rem .375rem;background:#f3f4f6;color:#374151;border-radius:.25rem;font-size:.625rem;font-family:monospace">{String.slice(
                            uuid,
                            0..7
                          )}</span>
                        <% end %>
                        <%= if entry.candidates == [] do %>
                          <span style="font-size:.75rem;color:#d1d5db">—</span>
                        <% end %>
                      </div>
                    </td>
                    <td style="padding:.625rem 1rem">
                      <%= if entry.preferred do %>
                        <span style="display:inline-flex;align-items:center;gap:.25rem;padding:.125rem .5rem;background:#ecfdf5;color:#065f46;border-radius:9999px;font-size:.75rem;font-weight:500">✓ {String.slice(
                          entry.preferred,
                          0..11
                        )}</span>
                      <% else %>
                        <span style="font-size:.75rem;color:#9ca3af">none</span>
                      <% end %>
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
