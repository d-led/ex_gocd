defmodule ExGoCDWeb.ConfigDiffLive do
  @moduledoc """
  Side-by-side config change diff viewer for pipeline runs.

  Shows what changed in the pipeline configuration between two runs.
  Mirrors GoCD's "Config Changes" feature in pipeline history.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.Pipelines

  @impl true
  def mount(params, _session, socket) do
    pipeline_name = params["pipeline_name"]
    counter = String.to_integer(params["counter"])

    {:ok,
     socket
     |> assign(:pipeline_name, pipeline_name)
     |> assign(:counter, counter)
     |> assign(:diff, nil)
     |> assign(:error, nil)
     |> assign(:loading, true)
     |> load_diff()}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  defp load_diff(socket) do
    case Pipelines.config_diff(socket.assigns.pipeline_name, socket.assigns.counter) do
      {:ok, diff} ->
        assign(socket, diff: diff, loading: false)

      {:error, reason} ->
        assign(socket, error: reason, loading: false)
    end
  end

  # ── Diff Rendering Helpers ─────────────────────────────────────────────

  defp flatten_diff(diff, prefix \\ []) do
    case diff do
      nil ->
        []

      map when is_map(map) ->
        Enum.flat_map(map, fn {key, change} ->
          path = prefix ++ [to_string(key)]

          case change do
            :equal ->
              []

            :added ->
              [{:added, path, nil}]

            :removed ->
              [{:removed, path, nil}]

            {:primitive_change, old_val, new_val} ->
              [{:changed, path, old_val, new_val}]

            nested when is_map(nested) ->
              flatten_diff(nested, path)
          end
        end)

      _ ->
        []
    end
  end

  defp path_to_string(path), do: Enum.join(path, " → ")

  defp format_val(val) when is_binary(val), do: val
  defp format_val(val) when is_number(val), do: to_string(val)
  defp format_val(val) when is_boolean(val), do: to_string(val)
  defp format_val(nil), do: "—"
  defp format_val(val), do: inspect(val, limit: 100)

  defp section_label(path) do
    case path do
      ["stages", stage_name | rest] ->
        "Stage: #{stage_name} → #{Enum.join(rest, " → ")}"

      ["materials", mat_name | rest] ->
        "Material: #{mat_name} → #{Enum.join(rest, " → ")}"

      _ ->
        path_to_string(path)
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f2f2f2]">
      <div class="max-w-5xl mx-auto pt-6 px-4">
        <%!-- Breadcrumbs --%>
        <nav class="flex items-center gap-1 text-xs text-slate-400 mb-4" aria-label="Breadcrumb">
          <.link
            navigate={~p"/pipeline/activity/#{@pipeline_name}"}
            class="text-[#943a9e] hover:underline"
          >
            {@pipeline_name}
          </.link>
          <span>/</span>
          <span class="text-slate-600 font-medium">{@counter}</span>
          <span>/</span>
          <span class="text-slate-600">Config Changes</span>
        </nav>

        <h1 class="text-sm font-bold text-slate-700 mb-6">
          Config Changes: {@pipeline_name} #{@counter}
        </h1>

        <%= if @loading do %>
          <div class="bg-white rounded border border-[#d6e0e2] p-8 text-center text-slate-400 shadow-sm">
            <p class="text-sm">Loading config diff...</p>
          </div>
        <% else %>
          <%= if @error do %>
            <div class="bg-white rounded border border-[#d6e0e2] p-8 text-center shadow-sm">
              <p class="text-sm text-red-500">Error: {@error}</p>
            </div>
          <% else %>
            <%= if @diff == nil do %>
              <div class="bg-white rounded border border-[#d6e0e2] p-8 text-center text-slate-400 shadow-sm">
                <p class="text-sm">No configuration changes detected.</p>
                <p class="text-xs mt-1">
                  The pipeline configuration is identical to the previous run.
                </p>
              </div>
            <% else %>
              <% changes = flatten_diff(@diff) %>
              <%= if changes == [] do %>
                <div class="bg-white rounded border border-[#d6e0e2] p-8 text-center text-slate-400 shadow-sm">
                  <p class="text-sm">No configuration changes detected.</p>
                </div>
              <% else %>
                <div class="bg-white rounded border border-[#d6e0e2] shadow-sm overflow-hidden">
                  <div class="px-4 py-2 bg-slate-50 border-b border-[#d6e0e2] text-[10px] font-bold uppercase text-slate-500">
                    {length(changes)} change{unless length(changes) == 1, do: "s"}
                  </div>
                  <div class="divide-y divide-slate-100">
                    <%= for {type, path, old_val, new_val} <- changes do %>
                      <details class="group" open>
                        <summary class="px-4 py-2 cursor-pointer hover:bg-slate-50/50 flex items-center gap-2 select-none">
                          <span class="text-[10px] text-slate-300 group-open:rotate-90 transition-transform">
                            ▶
                          </span>
                          <span class={
                            case type do
                              :added ->
                                "text-[10px] font-bold uppercase px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700"

                              :removed ->
                                "text-[10px] font-bold uppercase px-1.5 py-0.5 rounded bg-red-50 text-red-700"

                              :changed ->
                                "text-[10px] font-bold uppercase px-1.5 py-0.5 rounded bg-amber-50 text-amber-700"
                            end
                          }>
                            {type}
                          </span>
                          <span class="text-xs text-slate-600 font-medium">
                            {section_label(path)}
                          </span>
                        </summary>
                        <div class="px-10 py-3 bg-slate-50/30">
                          <%= if type == :added do %>
                            <div class="text-xs">
                              <span class="text-slate-400">Added: </span>
                              <span class="text-emerald-700 font-mono">{format_val(new_val)}</span>
                            </div>
                          <% end %>
                          <%= if type == :removed do %>
                            <div class="text-xs">
                              <span class="text-slate-400">Was: </span>
                              <span class="text-red-700 font-mono line-through">
                                {format_val(old_val)}
                              </span>
                            </div>
                          <% end %>
                          <%= if type == :changed do %>
                            <div class="grid grid-cols-2 gap-4 text-xs">
                              <div class="bg-red-50/50 rounded p-2 border border-red-100">
                                <div class="text-[10px] font-bold uppercase text-red-400 mb-1">
                                  Before
                                </div>
                                <div class="text-red-700 font-mono break-all">
                                  {format_val(old_val)}
                                </div>
                              </div>
                              <div class="bg-emerald-50/50 rounded p-2 border border-emerald-100">
                                <div class="text-[10px] font-bold uppercase text-emerald-400 mb-1">
                                  After
                                </div>
                                <div class="text-emerald-700 font-mono break-all">
                                  {format_val(new_val)}
                                </div>
                              </div>
                            </div>
                          <% end %>
                        </div>
                      </details>
                    <% end %>
                  </div>
                </div>
              <% end %>
            <% end %>
          <% end %>
        <% end %>

        <%!-- Back link --%>
        <div class="mt-4">
          <.link
            navigate={~p"/pipeline/activity/#{@pipeline_name}"}
            class="text-xs text-[#943a9e] hover:underline"
          >
            ← Back to pipeline activity
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
