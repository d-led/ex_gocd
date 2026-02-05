defmodule ExGoCDWeb.DashboardLive do
  use ExGoCDWeb, :live_view

  alias ExGoCD.MockData

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Pipelines")
     |> assign(:search_text, "")
     |> assign(:grouping_scheme, "environment")
     |> assign(:grouping_text, "Environment")
     |> assign(:dropdown_open, false)
     |> load_pipelines()}
  end

  @impl true
  def handle_event("search", %{"value" => search_text}, socket) do
    {:noreply,
     socket
     |> assign(:search_text, search_text)
     |> load_pipelines()}
  end

  @impl true
  def handle_event("toggle_dropdown", _params, socket) do
    {:noreply, assign(socket, :dropdown_open, !socket.assigns.dropdown_open)}
  end

  @impl true
  def handle_event("close_dropdown", _params, socket) do
    {:noreply, assign(socket, :dropdown_open, false)}
  end

  @impl true
  def handle_event("select_grouping", %{"scheme" => scheme}, socket) do
    text =
      case scheme do
        "environment" -> "Environment"
        "pipeline_group" -> "Pipeline Group"
        _ -> "Environment"
      end

    {:noreply,
     socket
     |> assign(:grouping_scheme, scheme)
     |> assign(:grouping_text, text)
     |> assign(:dropdown_open, false)
     |> load_pipelines()}
  end

  # Private functions

  defp load_pipelines(socket) do
    all_pipelines = MockData.pipelines()
    filtered = MockData.filter_pipelines(all_pipelines, socket.assigns.search_text)

    grouped =
      case socket.assigns.grouping_scheme do
        "environment" -> group_pipelines(filtered, MockData.pipelines_by_environment())
        "pipeline_group" -> group_pipelines(filtered, MockData.pipelines_by_group())
        _ -> group_pipelines(filtered, MockData.pipelines_by_environment())
      end

    socket
    |> assign(:pipeline_groups, grouped)
    |> assign(:has_pipelines, length(filtered) > 0)
  end

  defp group_pipelines(filtered_pipelines, grouped_data) do
    filtered_names = MapSet.new(filtered_pipelines, & &1.name)

    grouped_data
    |> Enum.map(fn {group_name, pipelines} ->
      filtered_group_pipelines =
        Enum.filter(pipelines, fn p -> MapSet.member?(filtered_names, p.name) end)

      {group_name, filtered_group_pipelines}
    end)
    |> Enum.reject(fn {_group, pipelines} -> Enum.empty?(pipelines) end)
  end

  # Component functions

  defp pipeline_group(assigns) do
    ~H"""
    <div class="pipeline-group" role="region" aria-label={"Pipeline group: #{@name}"}>
      <h2 class="pipeline-group_title">
        {@name}
        <span class="pipeline-group_count">({length(@pipelines)})</span>
      </h2>
      <div class="pipeline-group_items">
        <%= for pipeline <- @pipelines do %>
          <.pipeline_card pipeline={pipeline} />
        <% end %>
      </div>
    </div>
    """
  end

  defp pipeline_card(assigns) do
    ~H"""
    <div
      class={"pipeline_card #{status_class(@pipeline.status)}"}
      role="article"
      aria-label={"Pipeline #{@pipeline.name}"}
    >
      <div class="pipeline_header">
        <h3 class="pipeline_name">
          <a href={"/pipelines/#{@pipeline.name}"} tabindex="0">
            {@pipeline.name}
          </a>
        </h3>
        <div class="pipeline_info">
          <span class="pipeline_counter">#{@pipeline.counter}</span>
          <span class="pipeline_status">{@pipeline.status}</span>
        </div>
      </div>
      <div class="pipeline_stages">
        <%= for stage <- @pipeline.stages do %>
          <.stage_indicator stage={stage} />
        <% end %>
      </div>
      <div class="pipeline_meta">
        <span class="pipeline_time">
          {format_time(@pipeline.last_run)}
        </span>
      </div>
    </div>
    """
  end

  defp stage_indicator(assigns) do
    ~H"""
    <div
      class={"stage_indicator stage_#{String.downcase(@stage.status)}"}
      title={"#{@stage.name}: #{@stage.status}"}
      role="status"
      aria-label={"Stage #{@stage.name} is #{@stage.status}"}
    >
      <div class="stage_name">{@stage.name}</div>
      <div class="stage_status">{status_icon(@stage.status)}</div>
      <%= if @stage.duration do %>
        <div class="stage_duration">{format_duration(@stage.duration)}</div>
      <% end %>
    </div>
    """
  end

  defp status_class(status) do
    case status do
      "Passed" -> "pipeline_passed"
      "Failed" -> "pipeline_failed"
      "Building" -> "pipeline_building"
      _ -> "pipeline_unknown"
    end
  end

  defp status_icon(status) do
    case status do
      "Passed" -> "✓"
      "Failed" -> "✗"
      "Building" -> "⟳"
      "Cancelled" -> "⊘"
      _ -> "○"
    end
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%b %d, %H:%M")
  end

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end
end
