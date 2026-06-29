defmodule ExGoCDWeb.CompareLive do
  use ExGoCDWeb, :live_view

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.PipelineInstance
  alias ExGoCD.Repo

  import Ecto.Query

  @impl true
  def mount(%{"pipeline_name" => name} = params, _session, socket) do
    from_counter = params["from_counter"] && String.to_integer(params["from_counter"])
    to_counter = params["to_counter"] && String.to_integer(params["to_counter"])

    instances = list_instances(name)

    comparison =
      if from_counter && to_counter do
        load_comparison(name, from_counter, to_counter)
      end

    {:ok,
     socket
     |> assign(:pipeline_name, name)
     |> assign(:instances, instances)
     |> assign(:from_counter, from_counter)
     |> assign(:to_counter, to_counter)
     |> assign(:comparison, comparison)
     |> assign(:page_title, page_title(name, from_counter, to_counter))}
  end

  @impl true
  def handle_event("select_from", %{"counter" => counter}, socket) do
    from = String.to_integer(counter)
    to = socket.assigns.to_counter

    {:noreply,
     socket
     |> assign(:from_counter, from)
     |> maybe_compare(from, to)}
  end

  def handle_event("select_to", %{"counter" => counter}, socket) do
    to = String.to_integer(counter)
    from = socket.assigns.from_counter

    {:noreply,
     socket
     |> assign(:to_counter, to)
     |> maybe_compare(from, to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="compare-page px-8 py-8 bg-[#f4f8f9] min-h-screen font-sans">
      <div class="page-header border-b border-gray-200 pb-4 mb-6">
        <div class="flex items-center gap-2 text-xs text-gray-500 font-mono font-bold uppercase tracking-wider">
          <.link
            navigate={~p"/pipeline/activity/#{@pipeline_name}"}
            class="text-[#2d6ca2] hover:underline"
          >
            {@pipeline_name}
          </.link>
          <span>/</span>
          <span class="text-gray-800">Compare</span>
        </div>
        <h1 class="text-2xl font-extrabold text-gray-950 font-mono mt-2">
          Compare: {@pipeline_name}
        </h1>
      </div>

      <%!-- Instance Pickers --%>
      <div class="bg-white border border-gray-200 rounded shadow-sm p-5 mb-6">
        <div class="flex items-end gap-6 flex-wrap">
          <div class="flex-1 min-w-[200px]">
            <label class="block text-xs font-bold text-gray-500 uppercase tracking-wide mb-1.5">
              From Instance
            </label>
            <select
              id="from-picker"
              class="w-full border border-gray-300 rounded py-2 px-3 text-sm font-mono bg-white focus:ring-2 focus:ring-[#2d6ca2] focus:border-[#2d6ca2]"
              phx-change="select_from"
            >
              <option value="">Select counter...</option>
              <%= for inst <- @instances do %>
                <option value={inst.counter} selected={@from_counter == inst.counter}>
                  ##{inst.counter} — {inst.label || inst.status || "N/A"}
                </option>
              <% end %>
            </select>
          </div>

          <div class="flex items-center pb-2">
            <svg class="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M14 5l7 7m0 0l-7 7m7-7H3"
              />
            </svg>
          </div>

          <div class="flex-1 min-w-[200px]">
            <label class="block text-xs font-bold text-gray-500 uppercase tracking-wide mb-1.5">
              To Instance
            </label>
            <select
              id="to-picker"
              class="w-full border border-gray-300 rounded py-2 px-3 text-sm font-mono bg-white focus:ring-2 focus:ring-[#2d6ca2] focus:border-[#2d6ca2]"
              phx-change="select_to"
            >
              <option value="">Select counter...</option>
              <%= for inst <- @instances do %>
                <option value={inst.counter} selected={@to_counter == inst.counter}>
                  ##{inst.counter} — {inst.label || inst.status || "N/A"}
                </option>
              <% end %>
            </select>
          </div>
        </div>
        <p class="text-xs text-gray-400 mt-3">
          Pick any two instances to compare materials, environment variables, and config changes.
        </p>
      </div>

      <%= if @comparison do %>
        <%= if Enum.empty?(@comparison.materials) do %>
          <div class="bg-white border border-gray-200 rounded shadow-sm p-8 text-center text-gray-500 italic">
            No materials configuration or changes found to compare.
          </div>
        <% else %>
          <!-- Header -->
          <div class="flex items-center gap-2 mb-4">
            <span class="text-sm font-bold text-gray-800">
              Counter
              <span class="bg-gray-200 px-1.5 py-0.5 rounded text-gray-800">{@from_counter}</span>
              →
              <span class="bg-[#e7eef0] px-1.5 py-0.5 rounded text-[#2d6ca2] font-bold">
                {@to_counter}
              </span>
            </span>
          </div>

          <div class="flex flex-col gap-6">
            <%= for mat <- @comparison.materials do %>
              <div class="bg-white border border-gray-200 rounded shadow-sm overflow-hidden">
                <div class="bg-gray-50 border-b border-gray-200 px-6 py-4 flex justify-between items-center flex-wrap gap-2">
                  <div>
                    <h3 class="text-sm font-bold text-gray-800 flex items-center gap-2">
                      <span class="bg-[#2d6ca2] text-white text-[10px] uppercase font-bold px-2 py-0.5 rounded tracking-wide font-mono">
                        {mat.type}
                      </span>
                      <span class="font-mono text-xs text-gray-600">{mat.url}</span>
                      <span class="text-xs text-gray-400 font-normal">[{mat.branch}]</span>
                    </h3>
                  </div>
                  <div class="text-[10px] font-mono text-gray-400 font-bold uppercase tracking-wider flex gap-4">
                    <div>
                      From:
                      <span class="text-gray-700 font-semibold">
                        {format_revision(mat.from_revision)}
                      </span>
                    </div>
                    <div>
                      To:
                      <span class="text-gray-700 font-semibold">
                        {format_revision(mat.to_revision)}
                      </span>
                    </div>
                  </div>
                </div>
                <div class="p-0">
                  <%= if Enum.empty?(mat.modifications) do %>
                    <div class="p-6 text-center text-gray-400 italic text-xs">
                      No modifications found.
                    </div>
                  <% else %>
                    <table class="min-w-full divide-y divide-gray-200 text-xs text-left">
                      <thead>
                        <tr class="bg-gray-50/50 text-[10px] uppercase font-bold text-gray-400 tracking-wider font-mono border-b border-gray-200">
                          <th class="px-6 py-3 w-40">Revision</th>
                          <th class="px-6 py-3 w-48">Author</th>
                          <th class="px-6 py-3">Comment</th>
                          <th class="px-6 py-3 text-right w-48">Modified Time</th>
                        </tr>
                      </thead>
                      <tbody class="divide-y divide-gray-100 font-mono text-gray-700">
                        <%= for mod <- mat.modifications do %>
                          <tr class="hover:bg-gray-50/50">
                            <td class="px-6 py-3.5 font-bold text-[#2d6ca2]">
                              {format_revision(mod["revision"])}
                            </td>
                            <td class="px-6 py-3.5 text-gray-800 font-semibold">{mod["username"]}</td>
                            <td class="px-6 py-3.5 text-gray-600 font-sans whitespace-pre-wrap">
                              {mod["comment"]}
                            </td>
                            <td class="px-6 py-3.5 text-gray-400 text-right">
                              {format_time(mod["modifiedTime"])}
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Environment Variables --%>
          <%= if @comparison.from_environment_variables != [] or @comparison.to_environment_variables != [] do %>
            <div class="bg-white border border-gray-200 rounded shadow-sm overflow-hidden mt-6">
              <div class="bg-gray-50 border-b border-gray-200 px-6 py-4">
                <h3 class="text-sm font-bold text-gray-800">🔧 Environment Variables</h3>
              </div>
              <div class="grid grid-cols-2 divide-x divide-gray-200">
                <div class="p-4">
                  <div class="text-[10px] font-bold uppercase text-gray-400 mb-3">
                    From (##{@from_counter})
                  </div>
                  <%= if @comparison.from_environment_variables == [] do %>
                    <div class="text-xs text-gray-400 italic">No variables</div>
                  <% else %>
                    <div class="space-y-1">
                      <%= for var <- @comparison.from_environment_variables do %>
                        <div class="flex items-center gap-2 text-xs">
                          <span class="font-mono text-gray-700 font-semibold">{var["name"]}</span>
                          <span class="text-gray-400">=</span>
                          <span class="font-mono text-gray-500 break-all">{var["value"]}</span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
                <div class="p-4">
                  <div class="text-[10px] font-bold uppercase text-[#2d6ca2] mb-3">
                    To (##{@to_counter})
                  </div>
                  <%= if @comparison.to_environment_variables == [] do %>
                    <div class="text-xs text-gray-400 italic">No variables</div>
                  <% else %>
                    <div class="space-y-1">
                      <%= for var <- @comparison.to_environment_variables do %>
                        <div class="flex items-center gap-2 text-xs">
                          <span class="font-mono text-gray-700 font-semibold">{var["name"]}</span>
                          <span class="text-gray-400">=</span>
                          <span class="font-mono text-gray-500 break-all">{var["value"]}</span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Config Changed --%>
          <%= if @comparison.config_changed do %>
            <div class="flex items-center gap-2 bg-purple-50 border border-purple-200 rounded px-4 py-3 text-xs mt-6">
              <span class="text-purple-700 font-medium">
                ⚙ Pipeline configuration changed between these runs.
              </span>
              <.link
                navigate={~p"/pipelines/#{@pipeline_name}/#{@to_counter}/config_diff"}
                class="text-[#943a9e] hover:underline font-bold ml-auto"
              >
                View config diff →
              </.link>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ── Private helpers ─────────────────────────────────────────────────────

  defp list_instances(name) do
    Repo.all(
      from pi in PipelineInstance,
        join: p in assoc(pi, :pipeline),
        where: p.name == ^name,
        order_by: [desc: pi.counter],
        limit: 50,
        select: %{counter: pi.counter, label: pi.label, status: pi.status}
    )
  end

  defp load_comparison(name, from, to) do
    Pipelines.compare_instances(name, from, to)
  rescue
    _ ->
      %{
        materials: [],
        from_environment_variables: [],
        to_environment_variables: [],
        config_changed: false
      }
  end

  defp maybe_compare(socket, from, to) when is_integer(from) and is_integer(to) do
    comparison = load_comparison(socket.assigns.pipeline_name, from, to)

    assign(socket,
      comparison: comparison,
      page_title: page_title(socket.assigns.pipeline_name, from, to)
    )
  end

  defp maybe_compare(socket, _from, _to), do: socket

  defp page_title(name, nil, _), do: "Compare #{name}"
  defp page_title(name, _, nil), do: "Compare #{name}"
  defp page_title(name, from, to), do: "Compare #{name}: #{from}→#{to}"

  defp format_revision(rev) when is_binary(rev) do
    if String.length(rev) > 10, do: String.slice(rev, 0, 8), else: rev
  end

  defp format_revision(_), do: "Unknown"

  defp format_time(nil), do: "—"

  defp format_time(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%d %b, %Y at %H:%M:%S UTC")
      _ -> time
    end
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%d %b, %Y at %H:%M:%S UTC")
  defp format_time(_), do: "—"
end
