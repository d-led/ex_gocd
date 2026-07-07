defmodule ExGoCDWeb.GanttLive do
  use ExGoCDWeb, :live_view

  alias ExGoCD.Pipelines.{PipelineInstance, StageInstance}
  alias ExGoCD.Repo

  import Ecto.Query

  # Chart dimensions
  @chart_w 600
  @chart_h 200
  @margin_left 40
  @margin_right 20
  @margin_top 10
  @margin_bottom 24

  @max_runs 30

  @impl true
  def mount(%{"pipeline_name" => pipeline_name}, _session, socket) do
    charts = build_duration_charts(pipeline_name)

    socket =
      socket
      |> assign(:pipeline_name, pipeline_name)
      |> assign(:charts, charts)
      |> assign(:page_title, "#{pipeline_name} — Stage Duration")

    if connected?(socket), do: :timer.send_interval(30_000, :refresh)

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    charts = build_duration_charts(socket.assigns.pipeline_name)
    {:noreply, assign(socket, charts: charts)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="px-4 sm:px-8 py-4 sm:py-8 bg-[#f4f8f9] min-h-screen font-sans"
      data-test-id="gantt-page"
    >
      <div class="page-header border-b border-gray-200 pb-3 sm:pb-4 mb-4 sm:mb-6">
        <h1
          class="text-xl sm:text-2xl font-extrabold text-gray-950 font-mono"
          data-test-id="gantt-title"
        >
          {@pipeline_name}
          <span class="text-sm font-semibold text-gray-500 font-mono ml-2">Stage Duration</span>
        </h1>
        <p class="text-xs sm:text-sm text-gray-500 mt-1">
          Stage duration over pipeline runs. Auto-refreshes every 30s.
        </p>
      </div>

      <%= if @charts == [] do %>
        <div class="bg-white border border-gray-200 rounded shadow-sm p-8 sm:p-12 text-center text-gray-400">
          <p class="text-base sm:text-lg">No pipeline runs with completed stages yet.</p>
          <p class="text-xs sm:text-sm mt-1">
            Trigger a pipeline and wait for stages to pass or fail.
          </p>
        </div>
      <% else %>
        <div class="flex flex-col gap-6">
          <%= for chart <- @charts do %>
            <div class="bg-white border border-gray-200 rounded shadow-sm p-4 sm:p-6">
              <h2
                class="text-sm font-bold text-gray-800 mb-3 font-mono"
                data-test-id={"chart-stage-#{chart.stage_name}"}
              >
                <i class="fa-solid fa-chart-line text-[#2d6ca2] mr-1.5"></i>
                {chart.stage_name}
              </h2>
              <div class="flex items-center gap-4 mb-2 text-[10px] text-gray-500">
                <span class="flex items-center gap-1">
                  <span class="w-2.5 h-2.5 rounded" style="background-color:#78C42D"></span> Passed
                </span>
                <span class="flex items-center gap-1">
                  <span class="w-2.5 h-2.5 rounded" style="background-color:#FA2D2D"></span> Failed
                </span>
              </div>
              <div class="overflow-x-auto">
                {{:safe, chart.svg}}
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Data ──────────────────────────────────────────────────────────────

  defp build_duration_charts(pipeline_name) do
    instances = load_instances(pipeline_name)

    if instances == [] do
      []
    else
      # Discover all unique stage names across instances
      stage_names =
        instances
        |> Enum.flat_map(& &1.stages)
        |> Enum.map(& &1.name)
        |> Enum.uniq()
        |> Enum.sort()

      Enum.map(stage_names, fn stage_name ->
        data = build_stage_data(instances, stage_name)

        %{
          stage_name: stage_name,
          svg: render_duration_chart(data)
        }
      end)
    end
  end

  defp build_stage_data(instances, stage_name) do
    counters =
      instances
      |> Enum.map(& &1.counter)
      |> Enum.sort()
      |> Enum.uniq()

    # For each counter, find latest Passed and latest Failed for this stage
    # (matching GoCD: pick latest per counter+status, then unique by counter+status)
    stage_rows =
      instances
      |> Enum.flat_map(fn inst ->
        inst.stages
        |> Enum.filter(&(&1.name == stage_name))
        |> Enum.filter(&(&1.result in ["Passed", "Failed"]))
        |> Enum.map(fn s ->
          start_time = s.scheduled_at || s.created_time

          duration =
            if s.completed_at && start_time do
              DateTime.diff(s.completed_at, start_time, :second)
            else
              0
            end

          %{
            counter: inst.counter,
            result: s.result,
            duration: max(duration, 0)
          }
        end)
      end)

    # Sort by counter then pick latest per counter+status (last wins)
    sorted =
      stage_rows
      |> Enum.sort_by(&{&1.counter, &1.result})

    # unique by counter+result, keeping last (latest stage run)
    per_counter_status =
      sorted
      |> Enum.reverse()
      |> Enum.uniq_by(&{&1.counter, &1.result})
      |> Enum.reverse()

    # Build series: for each counter, what's the Passed and Failed duration?
    passed =
      per_counter_status
      |> Enum.filter(&(&1.result == "Passed"))
      |> Map.new(&{&1.counter, &1.duration})

    failed =
      per_counter_status
      |> Enum.filter(&(&1.result == "Failed"))
      |> Map.new(&{&1.counter, &1.duration})

    %{
      counters: counters,
      passed: Enum.map(counters, &Map.get(passed, &1, nil)),
      failed: Enum.map(counters, &Map.get(failed, &1, nil)),
      all_durations:
        per_counter_status
        |> Enum.map(& &1.duration)
        |> Enum.reject(&(&1 == 0))
    }
  end

  # ── SVG Line Chart ────────────────────────────────────────────────────

  defp render_duration_chart(%{
         counters: counters,
         passed: passed,
         failed: failed,
         all_durations: all_durations
       }) do
    max_dur = if all_durations == [], do: 1, else: Enum.max(all_durations)
    # Round up to nice scale
    {y_max, unit} = nice_scale(max_dur)

    n = length(counters)

    svg_w = @chart_w + @margin_left + @margin_right
    svg_h = @chart_h + @margin_top + @margin_bottom

    # Chart area
    plot_w = @chart_w
    plot_h = @chart_h

    x = fn i -> @margin_left + round(i / max(n - 1, 1) * plot_w) end
    y = fn dur -> @margin_top + plot_h - round(dur / y_max * plot_h) end

    # Grid lines
    grid =
      for tick <- 0..4 do
        ty = @margin_top + round(tick / 4 * plot_h)
        val = round(y_max * (1 - tick / 4))

        [
          ~s'<line x1="#{@margin_left}" y1="#{ty}" x2="#{@margin_left + plot_w}" y2="#{ty}" stroke="#e5e7eb" stroke-width="1"/>',
          ~s'<text x="#{@margin_left - 4}" y="#{ty + 3}" font-size="9" fill="#9ca3af" text-anchor="end" font-family="monospace">#{val}#{unit}</text>'
        ]
      end
      |> List.flatten()

    # X-axis labels: every Nth counter
    step = max(div(n, 6), 1)

    x_labels =
      counters
      |> Enum.with_index()
      |> Enum.filter(fn {_, i} -> rem(i, step) == 0 end)
      |> Enum.map(fn {c, i} ->
        ~s'<text x="#{x.(i)}" y="#{@margin_top + plot_h + 14}" font-size="9" fill="#9ca3af" text-anchor="middle" font-family="monospace">#{c}</text>'
      end)

    # Passed line
    passed_points = build_line(passed, counters, n, x, y)
    passed_line = build_polyline(passed_points, "#78C42D")

    # Failed line
    failed_points = build_line(failed, counters, n, x, y)
    failed_line = build_polyline(failed_points, "#FA2D2D")

    # DOT markers
    passed_dots = build_dots(passed_points, "#78C42D")
    failed_dots = build_dots(failed_points, "#FA2D2D")

    # Axes
    axes = [
      ~s'<line x1="#{@margin_left}" y1="#{@margin_top}" x2="#{@margin_left}" y2="#{@margin_top + plot_h}" stroke="#d1d5db" stroke-width="1"/>',
      ~s'<line x1="#{@margin_left}" y1="#{@margin_top + plot_h}" x2="#{@margin_left + plot_w}" y2="#{@margin_top + plot_h}" stroke="#d1d5db" stroke-width="1"/>'
    ]

    parts = [grid, axes, x_labels, failed_line, passed_line, failed_dots, passed_dots]

    ~s'<svg viewBox="0 0 #{svg_w} #{svg_h}" width="100%" style="max-height:#{svg_h}px" xmlns="http://www.w3.org/2000/svg">\n#{Enum.join(parts, "\n")}\n</svg>'
  end

  defp build_line(series, counters, _n, x, y) do
    counters
    |> Enum.with_index()
    |> Enum.map(fn {_c, i} ->
      case Enum.at(series, i) do
        nil -> nil
        dur -> {x.(i), y.(dur)}
      end
    end)
  end

  defp build_polyline(points, color) do
    valid = Enum.filter(points, &(&1 != nil))

    if length(valid) < 2 do
      ""
    else
      path = valid |> Enum.map(fn {px, py} -> "#{px},#{py}" end) |> Enum.join(" ")

      ~s'<polyline points="#{path}" fill="none" stroke="#{color}" stroke-width="2" stroke-linejoin="round"/>'
    end
  end

  defp build_dots(points, color) do
    points
    |> Enum.filter(&(&1 != nil))
    |> Enum.map(fn {px, py} ->
      ~s'<circle cx="#{px}" cy="#{py}" r="3" fill="#{color}"><title>#{py}</title></circle>'
    end)
    |> Enum.join("\n")
  end

  defp nice_scale(max_dur) when max_dur < 60, do: {max(max_dur, 10), "s"}
  defp nice_scale(max_dur) when max_dur < 600, do: {ceil(max_dur / 60) * 60, "s"}
  defp nice_scale(max_dur), do: {ceil(max_dur / 60) * 60, "s"}

  # ── Database ──────────────────────────────────────────────────────────

  defp load_instances(pipeline_name) do
    Repo.all(
      from pi in PipelineInstance,
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name,
        left_join: si in assoc(pi, :stage_instances),
        order_by: [desc: pi.inserted_at, asc: si.inserted_at],
        limit: @max_runs,
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
              scheduled_at: s.scheduled_at,
              completed_at: s.completed_at,
              created_time: s.created_time,
              updated_at: s.updated_at
            }
          end)
      }
    end)
  end
end
