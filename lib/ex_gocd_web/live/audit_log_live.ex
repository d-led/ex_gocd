defmodule ExGoCDWeb.AuditLogLive do
  @moduledoc """
  Searchable audit log viewer. Lists all administrative and pipeline actions
  with filters for actor, action, resource type, and date range.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.AuditLog

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit Log")
     |> assign(:entries, [])
     |> assign(:total, 0)
     |> assign(:page, 1)
     |> assign(:filters, %{})
     |> assign(:actor, "")
     |> assign(:action, "")
     |> assign(:resource_type, "")
     |> assign(:resource_name, "")
     |> assign(:date_from, "")
     |> assign(:date_to, "")
     |> load_entries()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:page, String.to_integer(params["page"] || "1"))
      |> assign(:actor, params["actor"] || "")
      |> assign(:action, params["action"] || "")
      |> assign(:resource_type, params["resource_type"] || "")
      |> assign(:resource_name, params["resource_name"] || "")
      |> assign(:date_from, params["date_from"] || "")
      |> assign(:date_to, params["date_to"] || "")
      |> load_entries()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{} = params, socket) do
    filters =
      %{}
      |> put_if(params, "actor")
      |> put_if(params, "action")
      |> put_if(params, "resource_type")
      |> put_if(params, "resource_name")

    date_from = parse_date(params["date_from"])
    date_to = parse_date(params["date_to"])

    filters =
      filters
      |> Map.put(:date_from, date_from)
      |> Map.put(:date_to, date_to)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:actor, params["actor"] || "")
     |> assign(:action, params["action"] || "")
     |> assign(:resource_type, params["resource_type"] || "")
     |> assign(:resource_name, params["resource_name"] || "")
     |> assign(:date_from, params["date_from"] || "")
     |> assign(:date_to, params["date_to"] || "")
     |> assign(:page, 1)
     |> load_entries()}
  end

  def handle_event("page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    {:noreply, assign(socket, :page, page) |> load_entries()}
  end

  # ── Data loading ───────────────────────────────────────────────────────────

  defp load_entries(socket) do
    entries = socket.assigns.filters
      |> then(fn
        f when f == %{} -> AuditLog.recent(@page_size)
        f -> AuditLog.search(f)
      end)

    socket
    |> assign(:entries, entries)
    |> assign(:total, length(entries))
  end

  defp put_if(map, _key, ""), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp parse_date(""), do: nil
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_time(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S")
  defp format_time(_), do: "—"

  defp action_badge("pipeline_trigger"), do: ~s|<span class="px-1.5 py-0.5 rounded text-[9px] font-bold bg-emerald-50 text-emerald-700">Trigger</span>|
  defp action_badge("stage_approve"), do: ~s|<span class="px-1.5 py-0.5 rounded text-[9px] font-bold bg-blue-50 text-blue-700">Approve</span>|
  defp action_badge("pipeline_pause"), do: ~s|<span class="px-1.5 py-0.5 rounded text-[9px] font-bold bg-amber-50 text-amber-700">Pause</span>|
  defp action_badge("pipeline_unpause"), do: ~s|<span class="px-1.5 py-0.5 rounded text-[9px] font-bold bg-emerald-50 text-emerald-700">Unpause</span>|
  defp action_badge("config_update"), do: ~s|<span class="px-1.5 py-0.5 rounded text-[9px] font-bold bg-purple-50 text-purple-700">Config</span>|
  defp action_badge("pipeline_delete"), do: ~s|<span class="px-1.5 py-0.5 rounded text-[9px] font-bold bg-red-50 text-red-700">Delete</span>|
  defp action_badge(other), do: ~s|<span class="px-1.5 py-0.5 rounded text-[9px] font-bold bg-slate-100 text-slate-600">#{other}</span>|

  defp resource_link("pipeline", name) do
    ~s|<a href="/pipeline/activity/#{name}" class="text-[#943a9e] hover:underline text-xs">#{name}</a>|
  end
  defp resource_link("stage", name), do: ~s|<span class="text-xs text-slate-600">#{name}</span>|
  defp resource_link("agent", name), do: ~s|<span class="text-xs text-slate-600">#{name}</span>|
  defp resource_link(_, name), do: ~s|<span class="text-xs text-slate-600">#{name}</span>|

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f2f2f2]">
      <div class="max-w-6xl mx-auto pt-6 px-4">
        <h1 class="text-sm font-bold text-slate-700 mb-6">Audit Log</h1>

        <%!-- Search form --%>
        <div class="bg-white rounded border border-[#d6e0e2] p-4 mb-6 shadow-sm">
          <form phx-change="search" class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <div>
              <label class="block text-[10px] font-bold uppercase text-slate-400 mb-1">Actor</label>
              <input type="text" name="actor" value={@actor} placeholder="username" class="w-full border border-[#d6e0e2] rounded px-2 py-1.5 text-xs" />
            </div>
            <div>
              <label class="block text-[10px] font-bold uppercase text-slate-400 mb-1">Action</label>
              <input type="text" name="action" value={@action} placeholder="pipeline_trigger" class="w-full border border-[#d6e0e2] rounded px-2 py-1.5 text-xs" />
            </div>
            <div>
              <label class="block text-[10px] font-bold uppercase text-slate-400 mb-1">Resource Type</label>
              <input type="text" name="resource_type" value={@resource_type} placeholder="pipeline" class="w-full border border-[#d6e0e2] rounded px-2 py-1.5 text-xs" />
            </div>
            <div>
              <label class="block text-[10px] font-bold uppercase text-slate-400 mb-1">Resource Name</label>
              <input type="text" name="resource_name" value={@resource_name} placeholder="my-pipeline" class="w-full border border-[#d6e0e2] rounded px-2 py-1.5 text-xs" />
            </div>
            <div>
              <label class="block text-[10px] font-bold uppercase text-slate-400 mb-1">From</label>
              <input type="date" name="date_from" value={@date_from} class="w-full border border-[#d6e0e2] rounded px-2 py-1.5 text-xs" />
            </div>
            <div>
              <label class="block text-[10px] font-bold uppercase text-slate-400 mb-1">To</label>
              <input type="date" name="date_to" value={@date_to} class="w-full border border-[#d6e0e2] rounded px-2 py-1.5 text-xs" />
            </div>
          </form>
        </div>

        <%!-- Results --%>
        <div class="bg-white rounded border border-[#d6e0e2] shadow-sm overflow-hidden">
          <%= if Enum.empty?(@entries) do %>
            <div class="text-center py-12 text-slate-400">
              <p class="text-sm">No audit entries found.</p>
              <p class="text-xs mt-1">Try adjusting your filters.</p>
            </div>
          <% else %>
            <table class="w-full text-xs">
              <thead>
                <tr class="bg-slate-50 border-b border-[#d6e0e2]">
                  <th class="text-left px-4 py-2 font-bold text-slate-500 uppercase text-[10px]">Time</th>
                  <th class="text-left px-4 py-2 font-bold text-slate-500 uppercase text-[10px]">Actor</th>
                  <th class="text-left px-4 py-2 font-bold text-slate-500 uppercase text-[10px]">Action</th>
                  <th class="text-left px-4 py-2 font-bold text-slate-500 uppercase text-[10px]">Resource</th>
                  <th class="text-left px-4 py-2 font-bold text-slate-500 uppercase text-[10px]">Details</th>
                </tr>
              </thead>
              <tbody>
                <%= for entry <- @entries do %>
                  <tr class="border-b border-slate-100 hover:bg-slate-50/50">
                    <td class="px-4 py-2 text-slate-500 tabular-nums whitespace-nowrap">
                      {format_time(entry.inserted_at)}
                    </td>
                    <td class="px-4 py-2 text-slate-700 font-medium">{entry.actor}</td>
                    <td class="px-4 py-2">
                      <%= Phoenix.HTML.raw(action_badge(entry.action)) %>
                    </td>
                    <td class="px-4 py-2">
                      <%= if entry.resource_type && entry.resource_name do %>
                        <%= Phoenix.HTML.raw(resource_link(entry.resource_type, entry.resource_name)) %>
                      <% else %>
                        <span class="text-slate-400">—</span>
                      <% end %>
                    </td>
                    <td class="px-4 py-2 text-slate-400 max-w-xs truncate">
                      <%= if entry.details && entry.details != %{} do %>
                        {inspect(entry.details)}
                      <% else %>
                        —
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
            <div class="px-4 py-2 bg-slate-50 border-t border-[#d6e0e2] text-[10px] text-slate-400">
              {length(@entries)} entries
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
