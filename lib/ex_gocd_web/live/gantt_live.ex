defmodule ExGoCDWeb.GanttLive do
  use ExGoCDWeb, :live_view

  alias ExGoCD.Repo
  alias ExGoCD.Pipelines.{PipelineInstance, StageInstance}

  import Ecto.Query

  @bar_height 28
  @row_height 36
  @label_width 160
  @chart_w 800

  @impl true
  def mount(_params, _session, socket) do
    {instances, gantt} = build_gantt_data()

    socket =
      socket
      |> assign(:instances, instances)
      |> assign(:gantt, gantt)
      |> assign(:page_title, "Pipeline Gantt Chart")

    if connected?(socket), do: :timer.send_interval(30_000, :refresh)

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {instances, gantt} = build_gantt_data()
    {:noreply, assign(socket, instances: instances, gantt: gantt)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-8 py-8 bg-[#f4f8f9] min-h-screen font-sans">
      <div class="page-header border-b border-gray-200 pb-4 mb-6">
        <h1 class="text-2xl font-extrabold text-gray-950 font-mono">Pipeline Gantt</h1>
        <p class="text-sm text-gray-500 mt-1">
          Timeline of recent pipeline runs. Auto-refreshes every 30s.
        </p>
      </div>

      <%= if @instances == [] do %>
        <div class="bg-white border border-gray-200 rounded shadow-sm p-12 text-center text-gray-400">
          <p class="text-lg">No pipeline runs yet.</p>
          <p class="text-sm mt-1">Trigger a pipeline to see it on the Gantt chart.</p>
        </div>
      <% else %>
        <div class="bg-white border border-gray-200 rounded shadow-sm overflow-x-auto">
          <div style="min-width: 800px">
            {{:safe, @gantt}}
          </div>
        </div>

        <div class="flex gap-6 mt-4 text-xs text-gray-500">
          <div class="flex items-center gap-1.5">
            <span class="h-3 w-3 rounded-sm bg-green-500"></span> Passed
          </div>
          <div class="flex items-center gap-1.5">
            <span class="h-3 w-3 rounded-sm bg-red-500"></span> Failed
          </div>
          <div class="flex items-center gap-1.5">
            <span class="h-3 w-3 rounded-sm bg-blue-500"></span> Building
          </div>
          <div class="flex items-center gap-1.5">
            <span class="h-3 w-3 rounded-sm bg-gray-300"></span> Pending
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp build_gantt_data do
    instances = load_instances()

    if instances == [] do
      {[], ""}
    else
      gantt_svg = render_gantt_svg(instances)
      {instances, gantt_svg}
    end
  end

  defp render_gantt_svg(instances) do
    now = DateTime.utc_now()
    starts = Enum.map(instances, & &1.inserted_at)
    ends = Enum.map(instances, &(&1.updated_at || &1.inserted_at))
    all_times = starts ++ ends ++ [now]

    min_t = Enum.min(all_times, DateTime, fn -> now end)
    max_t = Enum.max(all_times, DateTime, fn -> now end)
    total_ms = max(DateTime.diff(max_t, min_t, :millisecond), 1)

    svg_h = length(instances) * @row_height + 40

    # Time ticks
    parts =
      for i <- 0..10 do
        x = @label_width + round(i * @chart_w / 10)
        tick_time = DateTime.add(min_t, round(i * total_ms / 10), :millisecond)

        [
          ~s'<line x1="#{x}" y1="0" x2="#{x}" y2="#{svg_h}" stroke="#e5e7eb" stroke-width="1"/>',
          ~s'<text x="#{x}" y="14" font-size="10" fill="#9ca3af" text-anchor="middle" font-family="monospace">#{Calendar.strftime(tick_time, "%H:%M")}</text>'
        ]
      end
      |> List.flatten()
      |> Enum.join("\n")

    # Now line
    now_x = @label_width + round(DateTime.diff(now, min_t, :millisecond) / total_ms * @chart_w)

    now_line = [
      ~s'<line x1="#{now_x}" y1="20" x2="#{now_x}" y2="#{svg_h}" stroke="#ef4444" stroke-width="1.5" stroke-dasharray="4,3"/>',
      ~s'<text x="#{now_x}" y="18" font-size="9" fill="#ef4444" text-anchor="middle" font-family="monospace">NOW</text>'
    ]

    # Instance bars
    bars =
      instances
      |> Enum.with_index()
      |> Enum.map(fn {inst, row} ->
        y = 30 + row * @row_height
        inst_start = inst.inserted_at
        inst_end = inst.updated_at || inst_start

        x1 =
          @label_width +
            round(DateTime.diff(inst_start, min_t, :millisecond) / total_ms * @chart_w)

        x2 =
          @label_width + round(DateTime.diff(inst_end, min_t, :millisecond) / total_ms * @chart_w)

        bar_w = max(x2 - x1, 4)

        label =
          ~s'<text x="#{@label_width - 8}" y="#{y + @bar_height / 2 + 2}" font-size="11" fill="#374151" text-anchor="end" font-family="monospace" dominant-baseline="middle">#{inst.pipeline_name} ##{inst.counter}</text>'

        stage_rects =
          if inst.stages != [] do
            total_stage_ms = max(DateTime.diff(inst_end, inst_start, :millisecond), 1)

            inst.stages
            |> Enum.map(fn stage ->
              stage_start = stage.started_at || stage.inserted_at

              stage_end =
                stage.completed_at || stage.updated_at || DateTime.add(stage_start, 1, :second)

              sx1 =
                x1 +
                  round(
                    DateTime.diff(stage_start, inst_start, :millisecond) / total_stage_ms * bar_w
                  )

              sx2 =
                x1 +
                  round(
                    DateTime.diff(stage_end, inst_start, :millisecond) / total_stage_ms * bar_w
                  )

              sw = max(sx2 - sx1, 2)
              color = stage_color(stage.result)

              ~s'<rect x="#{sx1}" y="#{y + 4}" width="#{sw}" height="#{@bar_height - 8}" rx="3" fill="#{color}" opacity="0.85"><title>#{stage.name}: #{stage.result || "running"}</title></rect>'
            end)
          else
            [
              ~s'<rect x="#{x1}" y="#{y + 4}" width="#{bar_w}" height="#{@bar_height - 8}" rx="3" fill="#d1d5db" opacity="0.7"><title>No stages</title></rect>'
            ]
          end

        [label | stage_rects]
      end)
      |> List.flatten()

    [
      ~s'<svg viewBox="0 0 #{@chart_w + @label_width} #{svg_h}" width="100%" style="max-height:600px" xmlns="http://www.w3.org/2000/svg">',
      parts,
      now_line,
      bars,
      "</svg>"
    ]
    |> List.flatten()
    |> Enum.join("\n")
    |> then(&{:safe, &1})
  end

  defp stage_color("Passed"), do: "#22c55e"
  defp stage_color("Failed"), do: "#ef4444"
  defp stage_color("Building"), do: "#3b82f6"
  defp stage_color(_), do: "#d1d5db"

  defp load_instances do
    Repo.all(
      from pi in PipelineInstance,
        join: p in assoc(pi, :pipeline),
        left_join: si in assoc(pi, :stage_instances),
        order_by: [desc: pi.inserted_at, asc: si.inserted_at],
        limit: 30,
        preload: [
          pipeline: [],
          stage_instances: ^from(si in StageInstance, order_by: [asc: si.inserted_at])
        ],
        select: pi
    )
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.map(fn pi ->
      %{
        id: pi.id,
        counter: pi.counter,
        pipeline_name: pi.pipeline.name,
        inserted_at: pi.inserted_at,
        updated_at: pi.updated_at,
        stages:
          Enum.map(pi.stage_instances || [], fn s ->
            %{
              name: s.name,
              result: s.result,
              inserted_at: s.inserted_at,
              started_at: s.started_at,
              completed_at: s.completed_at,
              updated_at: s.updated_at
            }
          end)
      }
    end)
  end
end
