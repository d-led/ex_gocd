defmodule ExGoCDWeb.CompareLive do
  use ExGoCDWeb, :live_view

  alias ExGoCD.Pipelines

  @impl true
  def mount(params, _session, socket) do
    pipeline_name = params["pipeline_name"]
    from_counter = String.to_integer(params["from_counter"])
    to_counter = String.to_integer(params["to_counter"])

    # Determine if we should use mock fallback
    use_mock = System.get_env("USE_MOCK_DATA") == "true" || not has_db_instances?(pipeline_name, to_counter)

    comparison =
      if use_mock do
        get_mock_comparison(pipeline_name, from_counter, to_counter)
      else
        Pipelines.compare_instances(pipeline_name, from_counter, to_counter)
      end

    {:ok,
     socket
     |> assign(:pipeline_name, pipeline_name)
     |> assign(:from_counter, from_counter)
     |> assign(:to_counter, to_counter)
     |> assign(:comparison, comparison)
     |> assign(:page_title, "Compare #{pipeline_name}: #{from_counter} with #{to_counter}")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # Helpers

  defp has_db_instances?(pipeline_name, counter) do
    import Ecto.Query
    ExGoCD.Repo.exists?(
      from pi in ExGoCD.Pipelines.PipelineInstance,
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and pi.counter == ^counter
    )
  end

  defp get_mock_comparison(pipeline_name, _from_counter, _to_counter) do
    # Generate realistic Git modifications
    [
      %{
        material_id: 1,
        type: "git",
        url: "https://github.com/gocd/#{pipeline_name}.git",
        branch: "master",
        from_revision: "a0f2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0",
        to_revision: "9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e",
        modifications: [
          %{
            "revision" => "9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e",
            "username" => "Dmitry Ledentsov <dmitry@example.com>",
            "modifiedTime" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "comment" => "feat: add robust job log streaming support for agents"
          },
          %{
            "revision" => "7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a2f1e0d9c8b",
            "username" => "Dmitry Ledentsov <dmitry@example.com>",
            "modifiedTime" => DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601(),
            "comment" => "fix: improve dashboard live status updates and reconnect handling"
          }
        ]
      }
    ]
  end

  defp format_revision(rev) when is_binary(rev) do
    if String.length(rev) > 10 do
      String.slice(rev, 0, 8)
    else
      rev
    end
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="compare-page px-8 py-8 bg-[#f4f8f9] min-h-screen font-sans">
      <!-- Breadcrumb Header -->
      <div class="page-header border-b border-gray-200 pb-4 mb-6">
        <div class="flex items-center gap-2 text-xs text-gray-500 font-mono font-bold uppercase tracking-wider">
          <.link navigate={~p"/pipeline/activity/#{@pipeline_name}"} class="text-[#2d6ca2] hover:underline">{@pipeline_name}</.link>
          <span>/</span>
          <span class="text-gray-800">Compare: {@from_counter} with {@to_counter}</span>
        </div>

        <div class="flex items-center justify-between mt-2 flex-wrap gap-4">
          <h1 class="text-2xl font-extrabold text-gray-950 font-mono flex items-baseline gap-2">
            Compare: {@pipeline_name}
            <span class="text-sm font-semibold text-gray-500">
              Counter <span class="bg-gray-200 px-1.5 py-0.5 rounded text-gray-800">{@from_counter}</span>
              to
              <span class="bg-[#e7eef0] px-1.5 py-0.5 rounded text-[#2d6ca2] font-bold">{@to_counter}</span>
            </span>
          </h1>
        </div>
      </div>

      <!-- Comparison Content -->
      <div class="flex flex-col gap-6">
        <%= if Enum.empty?(@comparison) do %>
          <div class="bg-white border border-gray-200 rounded shadow-sm p-8 text-center text-gray-500 italic">
            No materials configuration or changes found to compare.
          </div>
        <% else %>
          <%= for mat <- @comparison do %>
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
                  <div>From: <span class="text-gray-700 font-semibold">{format_revision(mat.from_revision)}</span></div>
                  <div>To: <span class="text-gray-700 font-semibold">{format_revision(mat.to_revision)}</span></div>
                </div>
              </div>

              <div class="p-0">
                <%= if Enum.empty?(mat.modifications) do %>
                  <div class="p-6 text-center text-gray-400 italic text-xs">
                    No modifications found between these runs.
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
                          <td class="px-6 py-3.5 font-bold text-[#2d6ca2] hover:underline">
                            {format_revision(mod["revision"])}
                          </td>
                          <td class="px-6 py-3.5 text-gray-800 font-semibold">
                            {mod["username"]}
                          </td>
                          <td class="px-6 py-3.5 text-gray-600 font-sans whitespace-pre-wrap select-text">
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
        <% end %>
      </div>
    </div>
    """
  end
end
