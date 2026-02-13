defmodule ExGoCDWeb.DashboardLive do
  use ExGoCDWeb, :live_view

  alias ExGoCD.MockData

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Pipelines")
     |> assign(:current_path, "/pipelines")
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

  # Component functions - EXACT GoCD HTML structure

  defp pipeline_group(assigns) do
    ~H"""
    <div class="dashboard-group" role="region" aria-label={"Pipeline group: #{@name}"}>
      <div class="dashboard-group_title">
        <div class="dashboard-group_name">{@name}</div>
      </div>
      <ul class="dashboard-group_items">
        <%= for pipeline <- @pipelines do %>
          <li class="dashboard-group_pipeline">
            <.pipeline_widget pipeline={pipeline} />
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp pipeline_widget(assigns) do
    ~H"""
    <div class="pipeline">
      <div class="pipeline_header">
        <div class="pipeline_sub_header">
          <h3 class="pipeline_name">{@pipeline.name}</h3>
          <div class="pipeline_actions">
            <a
              aria-label={"Edit Configuration for Pipeline #{@pipeline.name}"}
              title="Edit Pipeline Configuration"
              href={"/admin/pipelines/#{@pipeline.name}/edit"}
              class="edit_config"
            >
            </a>
          </div>
        </div>
        <div>
          <ul class="pipeline_operations">
            <li>
              <button
                type="button"
                aria-label="Trigger Pipeline"
                title="Trigger Pipeline"
                class="button pipeline_btn play"
              >
              </button>
            </li>
            <li>
              <button
                type="button"
                aria-label="Trigger with Options"
                title="Trigger with Options"
                class="button pipeline_btn play_with_options"
              >
              </button>
            </li>
            <li>
              <button
                type="button"
                aria-label="Pause Pipeline"
                title="Pause Pipeline"
                class="button pipeline_btn pause"
              >
              </button>
            </li>
          </ul>
          <a href={"/pipeline/activity/#{@pipeline.name}"} class="pipeline_history">History</a>
        </div>
      </div>
      <div class="pipeline_instances">
        <.pipeline_instance pipeline={@pipeline} />
      </div>
    </div>
    """
  end

  defp pipeline_instance(assigns) do
    ~H"""
    <div class="pipeline_instance">
      <label class="pipeline_instance-label">Instance: {@pipeline.counter}</label>
      <div class="more_info">
        <ul class="info">
          <li>
            <a href={"/compare/#{@pipeline.name}/#{@pipeline.counter - 1}/with/#{@pipeline.counter}"}>
              Compare
            </a>
          </li>
          <li>
            <a aria-label="Changes" title="Changes">
              <span class="changes">Changes</span>
            </a>
          </li>
          <li>
            <a
              href={"/pipelines/value_stream_map/#{@pipeline.name}/#{@pipeline.counter}"}
              title="Value Stream Map"
            >
              VSM
            </a>
          </li>
        </ul>
      </div>
      <div class="pipeline_instance-details">
        <div>{@pipeline.triggered_by}</div>
        <div title={format_server_time(@pipeline.last_run)}>
          on {format_local_time(@pipeline.last_run)}
        </div>
      </div>
      <ul class="pipeline_stages">
        <%= for stage <- @pipeline.stages do %>
          <li class="pipeline_stage_manual_gate_wrapper">
            <a
              class={stage_class(stage.status)}
              title={stage_title(stage)}
              aria-label={stage_title(stage)}
            >
            </a>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp stage_class(status) do
    base = "pipeline_stage"

    case status do
      "Passed" -> "#{base} passed"
      "Failed" -> "#{base} failed"
      "Building" -> "#{base} building"
      "Cancelled" -> "#{base} cancelled"
      "NotRun" -> "#{base} unknown"
      _ -> "#{base} unknown"
    end
  end

  defp stage_title(stage) do
    "#{stage.name} (#{stage.status})"
  end

  defp format_local_time(datetime) do
    Calendar.strftime(datetime, "%d %b, %Y at %H:%M:%S Local Time")
  end

  defp format_server_time(datetime) do
    Calendar.strftime(datetime, "%d %b, %Y at %H:%M:%S +00:00 Server Time")
  end
end
