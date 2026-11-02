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
        data = build_stage_data(instances, stage_name, pipeline_name)

        %{
          stage_name: stage_name,
          svg: render_duration_chart(data)
        }
      end)
    end
  end

  defp build_stage_data(instances, stage_name, pipeline_name) do
    counters = counters_of(instances)
    latest = instances |> stage_rows(stage_name) |> latest_per_status()

    %{
      pipeline_name: %{name: pipeline_name},
      stage_name: stage_name,
      counters: counters,
      passed: series_for(latest, counters, "Passed"),
      failed: series_for(latest, counters, "Failed"),
      all_durations: durations_of(latest)
    }
  end

  defp counters_of(instances) do
    instances
    |> Enum.map(& &1.counter)
    |> Enum.sort()
    |> Enum.uniq()
  end

  # One row per finished run of this stage, across every pipeline counter.
  defp stage_rows(instances, stage_name) do
    Enum.flat_map(instances, fn instance ->
      instance.stages
      |> Enum.filter(&(&1.name == stage_name))
      |> Enum.filter(&(&1.result in ["Passed", "Failed"]))
      |> Enum.map(&stage_row(instance.counter, &1))
    end)
  end

  defp stage_row(pipeline_counter, stage) do
    %{
      counter: pipeline_counter,
      stage_counter: Map.get(stage, :counter, 1) || 1,
      result: stage.result,
      duration: stage_duration(stage)
    }
  end

  defp stage_duration(stage) do
    elapsed(stage.completed_at, stage.scheduled_at || stage.created_time)
  end

  defp elapsed(nil, _start), do: 0
  defp elapsed(_completed, nil), do: 0
  defp elapsed(completed, start), do: max(DateTime.diff(completed, start, :second), 0)

  # GoCD plots the latest run of each status per counter, so the last one wins.
  defp latest_per_status(rows) do
    rows
    |> Enum.sort_by(&{&1.counter, &1.result})
    |> Enum.reverse()
    |> Enum.uniq_by(&{&1.counter, &1.result})
    |> Enum.reverse()
  end

  defp series_for(rows, counters, status) do
    by_counter =
      rows
      |> Enum.filter(&(&1.result == status))
      |> Map.new(&{&1.counter, &1})

    Enum.map(counters, &Map.get(by_counter, &1))
  end

  defp durations_of(rows) do
    rows
    |> Enum.map(& &1.duration)
    |> Enum.reject(&(&1 == 0))
  end

  # ── SVG Line Chart ────────────────────────────────────────────────────

  defp render_duration_chart(%{
         pipeline_name: %{name: pipe_name},
         stage_name: stage_name,
         counters: counters,
         passed: passed,
         failed: failed,
         all_durations: all_durations
       }) do
    {y_max, unit} = nice_scale(longest(all_durations))
    passed_points = build_line(passed, counters, y_max)
    failed_points = build_line(failed, counters, y_max)

    parts = [
      chart_grid(y_max, unit),
      chart_axes(),
      chart_x_labels(counters),
      build_polyline(failed_points, "#FA2D2D"),
      build_polyline(passed_points, "#78C42D"),
      build_dots(failed_points, "#FA2D2D", pipe_name, stage_name),
      build_dots(passed_points, "#78C42D", pipe_name, stage_name)
    ]

    ~s'<svg viewBox="0 0 #{@chart_w + @margin_left + @margin_right} #{svg_height()}" width="100%" style="max-height:#{svg_height()}px" xmlns="http://www.w3.org/2000/svg">\n#{Enum.join(parts, "\n")}\n</svg>'
  end

  defp longest([]), do: 1
  defp longest(durations), do: Enum.max(durations)

  defp svg_height, do: @chart_h + @margin_top + @margin_bottom

  defp chart_grid(y_max, unit) do
    Enum.flat_map(0..4, &grid_line(&1, y_max, unit))
  end

  defp grid_line(tick, y_max, unit) do
    ty = @margin_top + round(tick / 4 * @chart_h)
    value = round(y_max * (1 - tick / 4))

    [
      ~s'<line x1="#{@margin_left}" y1="#{ty}" x2="#{@margin_left + @chart_w}" y2="#{ty}" stroke="#e5e7eb" stroke-width="1"/>',
      ~s'<text x="#{@margin_left - 4}" y="#{ty + 3}" font-size="9" fill="#9ca3af" text-anchor="end" font-family="monospace">#{format_tick(value, unit)}</text>'
    ]
  end

  defp chart_axes do
    bottom = @margin_top + @chart_h

    [
      ~s'<line x1="#{@margin_left}" y1="#{@margin_top}" x2="#{@margin_left}" y2="#{bottom}" stroke="#d1d5db" stroke-width="1"/>',
      ~s'<line x1="#{@margin_left}" y1="#{bottom}" x2="#{@margin_left + @chart_w}" y2="#{bottom}" stroke="#d1d5db" stroke-width="1"/>'
    ]
  end

  # Label every sixth counter: enough to read the axis, few enough not to smear.
  defp chart_x_labels(counters) do
    count = length(counters)
    step = max(div(count, 6), 1)

    counters
    |> Enum.with_index()
    |> Enum.filter(fn {_counter, index} -> rem(index, step) == 0 end)
    |> Enum.map(fn {counter, index} ->
      ~s'<text x="#{chart_x(index, count)}" y="#{@margin_top + @chart_h + 14}" font-size="9" fill="#9ca3af" text-anchor="middle" font-family="monospace">#{counter}</text>'
    end)
  end

  defp chart_x(index, count), do: @margin_left + round(index / max(count - 1, 1) * @chart_w)

  defp chart_y(duration, y_max), do: @margin_top + @chart_h - round(duration / y_max * @chart_h)

  defp build_line(series, counters, y_max) do
    count = length(counters)

    [counters, series]
    |> Enum.zip()
    |> Enum.with_index()
    |> Enum.reject(fn {{_counter, row}, _index} -> is_nil(row) end)
    |> Enum.map(fn {{counter, row}, index} ->
      {counter, chart_x(index, count), chart_y(row.duration, y_max), row.duration,
       row.stage_counter}
    end)
  end

  defp build_polyline(points, color) do
    if length(points) < 2 do
      ""
    else
      path =
        points
        |> Enum.map(fn {_counter, px, py, _dur, _sc} -> "#{px},#{py}" end)
        |> Enum.join(" ")

      ~s'<polyline points="#{path}" fill="none" stroke="#{color}" stroke-width="2" stroke-linejoin="round"/>'
    end
  end

  defp build_dots(points, color, pipe_name, stage_name) do
    points
    |> Enum.map(&dot(&1, color, pipe_name, stage_name))
    |> Enum.join("\n")
  end

  defp dot({counter, px, py, duration, stage_counter}, color, pipe_name, stage_name) do
    link = "/pipelines/#{pipe_name}/#{counter}/#{stage_name}/#{stage_counter}"

    ~s'<a href="#{link}">\n  <circle cx="#{px}" cy="#{py}" r="4" fill="#{color}" stroke="#fff" stroke-width="1" opacity="0.9" style="cursor:pointer">\n    <title>##{counter} #{stage_name}/#{stage_counter} — #{format_duration(duration)}</title>\n  </circle>\n</a>'
  end

  defp nice_scale(max_dur) when max_dur < 60, do: {max(max_dur, 10), :sec}
  defp nice_scale(max_dur) when max_dur < 3600, do: {ceil(max_dur / 60) * 60, :min}
  defp nice_scale(max_dur), do: {ceil(max_dur / 3600) * 3600, :hour}

  defp format_tick(val, :sec), do: "#{val}s"
  defp format_tick(val, :min), do: "#{div(val, 60)}m"
  defp format_tick(val, :hour), do: "#{div(val, 3600)}h"

  defp format_duration(sec) when sec < 60, do: "#{sec}s"
  defp format_duration(sec) when sec < 3600, do: "#{div(sec, 60)}m #{rem(sec, 60)}s"
  defp format_duration(sec), do: "#{div(sec, 3600)}h #{rem(div(sec, 60), 60)}m"

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
