defmodule ExGoCDWeb.DashboardLive do
  use ExGoCDWeb, :live_view

  alias ExGoCD.MockData
  alias ExGoCD.Pipelines

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ExGoCD.PubSub, "pipelines:updates")
    end

    {:ok,
     socket
     |> assign(:page_title, "Pipelines")
     |> assign(:current_path, "/pipelines")
     |> assign(:search_text, "")
     |> assign(:grouping_scheme, "environment")
     |> assign(:grouping_text, "Environment")
     |> assign(:dropdown_open, false)
     |> assign(:active_stage_summary, nil)
     |> assign(:selected_jobs, MapSet.new())
     |> assign(:show_pause_modal, false)
     |> assign(:active_pause_pipeline, nil)
     |> assign(:pause_cause_input, "")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search_text = params["search"] || ""
    {:noreply,
     socket
     |> assign(:search_text, search_text)
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

  @impl true
  def handle_event("trigger_pipeline", %{"name" => name}, socket) do
    user = socket.assigns[:current_user]

    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        result =
          if use_mock?() do
            {:ok, %{name: name}}
          else
            Pipelines.trigger_pipeline(name)
          end

        case result do
          {:ok, _instance} ->
            {:noreply,
             socket
             |> put_flash(:info, "Pipeline #{name} triggered. Jobs will run on idle agents.")
             |> load_pipelines()}

          {:error, :pipeline_not_found} ->
            {:noreply, put_flash(socket, :error, "Pipeline not found.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to trigger pipeline.")}
        end

      false ->
        {:noreply, put_flash(socket, :error, "You do not have operate permissions for this pipeline.")}
    end
  end

  @impl true
  def handle_event("show_pause_modal", %{"name" => name}, socket) do
    user = socket.assigns[:current_user]
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        {:noreply,
         socket
         |> assign(:show_pause_modal, true)
         |> assign(:active_pause_pipeline, name)
         |> assign(:pause_cause_input, "")}
      false ->
        {:noreply, put_flash(socket, :error, "You do not have operate permissions for this pipeline.")}
    end
  end

  @impl true
  def handle_event("close_pause_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_pause_modal, false)
     |> assign(:active_pause_pipeline, nil)
     |> assign(:pause_cause_input, "")}
  end

  @impl true
  def handle_event("pause_pipeline", %{"pause_cause" => cause}, socket) do
    pipeline_name = socket.assigns.active_pause_pipeline
    user = socket.assigns[:current_user]
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        username = (user && user.username) || "anonymous"
        # If running mock data, mock the pause behavior locally
        result =
          if use_mock?() do
            {:ok, nil}
          else
            Pipelines.pause_pipeline(pipeline_name, username, cause)
          end

        case result do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:show_pause_modal, false)
             |> assign(:active_pause_pipeline, nil)
             |> assign(:pause_cause_input, "")
             |> put_flash(:info, "Pipeline #{pipeline_name} paused successfully.")
             |> load_pipelines()}
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to pause pipeline.")}
        end
      false ->
        {:noreply, put_flash(socket, :error, "You do not have operate permissions for this pipeline.")}
    end
  end

  @impl true
  def handle_event("unpause_pipeline", %{"name" => name}, socket) do
    user = socket.assigns[:current_user]
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        result =
          if use_mock?() do
            {:ok, nil}
          else
            Pipelines.unpause_pipeline(name)
          end

        case result do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Pipeline #{name} unpaused successfully.")
             |> load_pipelines()}
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to unpause pipeline.")}
        end
      false ->
        {:noreply, put_flash(socket, :error, "You do not have operate permissions for this pipeline.")}
    end
  end

  @impl true
  def handle_event("show_stage_summary", %{"pipeline" => pipeline_name, "stage" => stage_name, "counter" => counter_str}, socket) do
    counter = String.to_integer(counter_str)
    summary = fetch_stage_summary_details(pipeline_name, counter, stage_name)
    {:noreply,
     socket
     |> assign(:active_stage_summary, summary)
     |> assign(:selected_jobs, MapSet.new())}
  end

  @impl true
  def handle_event("close_stage_summary", _params, socket) do
    {:noreply, assign(socket, :active_stage_summary, nil)}
  end

  @impl true
  def handle_event("toggle_job_selection", %{"job" => job_name}, socket) do
    selected = socket.assigns.selected_jobs
    new_selected =
      if MapSet.member?(selected, job_name) do
        MapSet.delete(selected, job_name)
      else
        MapSet.put(selected, job_name)
      end
    {:noreply, assign(socket, :selected_jobs, new_selected)}
  end

  @impl true
  def handle_event("rerun_failed_jobs", _params, socket) do
    summary = socket.assigns.active_stage_summary
    if summary do
      case Pipelines.rerun_stage(summary.pipeline_name, summary.pipeline_counter, summary.stage_name, :failed) do
        {:ok, _si} ->
          new_summary = fetch_stage_summary_details(summary.pipeline_name, summary.pipeline_counter, summary.stage_name)
          {:noreply,
           socket
           |> put_flash(:info, "Rerun failed jobs scheduled successfully.")
           |> assign(:active_stage_summary, new_summary)
           |> assign(:selected_jobs, MapSet.new())}
        {:error, :no_jobs_to_run} ->
          {:noreply, put_flash(socket, :error, "No failed or cancelled jobs found in previous stage run.")}
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to rerun jobs: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("rerun_selected_jobs", _params, socket) do
    summary = socket.assigns.active_stage_summary
    selected = socket.assigns.selected_jobs |> MapSet.to_list()
    if summary && not Enum.empty?(selected) do
      case Pipelines.rerun_stage(summary.pipeline_name, summary.pipeline_counter, summary.stage_name, selected) do
        {:ok, _si} ->
          new_summary = fetch_stage_summary_details(summary.pipeline_name, summary.pipeline_counter, summary.stage_name)
          {:noreply,
           socket
           |> put_flash(:info, "Rerun selected jobs scheduled successfully.")
           |> assign(:active_stage_summary, new_summary)
           |> assign(:selected_jobs, MapSet.new())}
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to rerun jobs: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :warning, "No jobs selected to rerun.")}
    end
  end

  @impl true
  def handle_event("approve_stage", %{"pipeline" => pipeline_name, "counter" => counter_str, "stage" => stage_name}, socket) do
    user = socket.assigns[:current_user]

    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        counter = String.to_integer(counter_str)
        case Pipelines.approve_stage(pipeline_name, counter, stage_name) do
          {:ok, _stage_instance} ->
            new_summary = fetch_stage_summary_details(pipeline_name, counter, stage_name)
            {:noreply,
             socket
             |> put_flash(:info, "Stage #{stage_name} approved successfully.")
             |> assign(:active_stage_summary, new_summary)
             |> load_pipelines()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to approve stage: #{inspect(reason)}")}
        end

      false ->
        {:noreply, put_flash(socket, :error, "You do not have operate permissions for this pipeline.")}
    end
  end

  @impl true
  def handle_info(:pipelines_updated, socket) do
    socket = load_pipelines(socket)
    socket =
      if summary = socket.assigns[:active_stage_summary] do
        new_summary = fetch_stage_summary_details(summary.pipeline_name, summary.pipeline_counter, summary.stage_name)
        assign(socket, :active_stage_summary, new_summary)
      else
        socket
      end
    {:noreply, socket}
  end

  # Fetch details helper
  defp fetch_stage_summary_details(pipeline_name, pipeline_counter, stage_name) do
    if use_mock?() do
      get_mock_stage_summary(pipeline_name, pipeline_counter, stage_name)
    else
      fetch_db_stage_summary(pipeline_name, pipeline_counter, stage_name)
    end
  end

  defp fetch_db_stage_summary(pipeline_name, pipeline_counter, stage_name) do
    import Ecto.Query
    pi =
      from(pi in ExGoCD.Pipelines.PipelineInstance,
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and pi.counter == ^pipeline_counter,
        preload: [:pipeline]
      )
      |> ExGoCD.Repo.one()

    with %{} = pi <- pi,
         si when not is_nil(si) <- find_latest_stage_instance(pi.id, stage_name) do
      build_stage_summary_map(pipeline_name, pipeline_counter, stage_name, pi, si)
    else
      _ -> get_mock_stage_summary(pipeline_name, pipeline_counter, stage_name)
    end
  end

  defp find_latest_stage_instance(pipeline_instance_id, stage_name) do
    import Ecto.Query
    from(si in ExGoCD.Pipelines.StageInstance,
      where: si.pipeline_instance_id == ^pipeline_instance_id and si.name == ^stage_name,
      order_by: [desc: si.counter],
      limit: 1,
      preload: [job_instances: :stage_instance]
    )
    |> ExGoCD.Repo.one()
  end

  defp build_stage_summary_map(pipeline_name, pipeline_counter, stage_name, pi, si) do
    build_cause = pi.build_cause || %{}
    triggered_by = build_cause["triggerMessage"] || "Triggered manually"
    created_time = si.created_time || si.inserted_at

    jobs = si.job_instances || []
    building_count = Enum.count(jobs, &(&1.state in ["Scheduled", "Assigned", "Preparing", "Building", "Completing"]))
    passed_count = Enum.count(jobs, &(&1.state == "Completed" and &1.result == "Passed"))
    failed_count = Enum.count(jobs, &(&1.state == "Completed" and &1.result in ["Failed", "Cancelled"]))

    mapped_jobs = Enum.map(jobs, &map_job_summary/1)

    %{
      pipeline_name: pipeline_name,
      pipeline_counter: pipeline_counter,
      stage_name: stage_name,
      stage_counter: si.counter,
      state: si.state,
      triggered_by: triggered_by,
      created_time: created_time,
      duration: stage_duration(si),
      building_count: building_count,
      passed_count: passed_count,
      failed_count: failed_count,
      jobs: mapped_jobs
    }
  end

  defp map_job_summary(ji) do
    %{
      name: ji.name,
      state: ji.state,
      result: ji.result,
      duration: job_duration(ji),
      agent_uuid: ji.agent_uuid
    }
  end

  defp job_duration(ji) do
    case {ji.completed_at, ji.assigned_at} do
      {completed, assigned} when not is_nil(completed) and not is_nil(assigned) ->
        DateTime.diff(to_utc_datetime(completed), to_utc_datetime(assigned), :second)
      _ ->
        0
    end
  end

  defp stage_duration(si) do
    case {si.completed_at, si.created_time} do
      {completed, created} when not is_nil(completed) and not is_nil(created) ->
        DateTime.diff(to_utc_datetime(completed), to_utc_datetime(created), :second)
      _ ->
        0
    end
  end

  defp to_utc_datetime(%DateTime{} = dt), do: dt
  defp to_utc_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp to_utc_datetime(_), do: nil

  defp get_mock_stage_summary(pipeline_name, pipeline_counter, stage_name) do
    %{
      pipeline_name: pipeline_name,
      pipeline_counter: pipeline_counter,
      stage_name: stage_name,
      stage_counter: 1,
      triggered_by: "Triggered by changes",
      created_time: DateTime.utc_now() |> DateTime.add(-71, :second),
      duration: 71,
      building_count: 0,
      passed_count: 1,
      failed_count: 0,
      jobs: [
        %{
          name: "unit-tests",
          state: "Completed",
          result: "Passed",
          duration: 71,
          agent_uuid: "107ba753edec"
        }
      ]
    }
  end
  # Private functions

  defp load_pipelines(socket) do
    {all_pipelines, from_db} = pipeline_list(socket)
    filtered = MockData.filter_pipelines(all_pipelines, socket.assigns.search_text)
    grouped_data = grouping_data(all_pipelines, socket.assigns.grouping_scheme, from_db)
    grouped = group_pipelines(filtered, grouped_data)

    socket
    |> assign(:pipeline_groups, grouped)
    |> assign(:has_pipelines, filtered != [])
  end

  defp use_mock? do
    System.get_env("USE_MOCK_DATA") == "true"
  end

  # Use DB pipelines when available, else mock data (same shape: name, group, counter, status, etc.)
  defp pipeline_list(_socket) do
    if use_mock?() do
      {MockData.pipelines(), false}
    else
      case Pipelines.list_for_dashboard() do
        [] -> {MockData.pipelines(), false}
        list -> {list, true}
      end
    end
  end

  defp grouping_data(_all_pipelines, "pipeline_group", false) do
    MockData.pipelines_by_group()
    |> Map.new()
  end

  defp grouping_data(_all_pipelines, "environment", false) do
    MockData.pipelines_by_environment()
    |> Map.new()
  end

  defp grouping_data(all_pipelines, "pipeline_group", true) do
    Enum.group_by(all_pipelines, &(Map.get(&1, :group) || "Default"))
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Map.new()
  end

  defp grouping_data(all_pipelines, "environment", true) do
    # Group by environment. Pipelines without an environment go under "Default".
    # When environments are implemented, this will use the actual environment assignment.
    env_map = Enum.group_by(all_pipelines, fn p ->
      env = Map.get(p, :environment) || p[:environment]
      if is_binary(env) and env != "", do: env, else: "Default"
    end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Map.new()

    # Ensure there's always at least a "Default" key for consistent rendering
    Map.put_new(env_map, "Default", [])
  end

  defp group_pipelines(filtered_pipelines, grouped_data) when is_map(grouped_data) do
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
    assigns = Map.put_new(assigns, :current_user, nil)
    ~H"""
    <div class="dashboard-group" role="region" aria-label={"Pipeline group: #{@name}"}>
      <div class="dashboard-group_title">
        <div class="dashboard-group_name">{@name}</div>
      </div>
      <ul class="dashboard-group_items">
        <%= for pipeline <- @pipelines do %>
          <li class="dashboard-group_pipeline">
            <.pipeline_widget pipeline={pipeline} current_user={@current_user} />
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp pipeline_widget(assigns) do
    assigns = Map.put_new(assigns, :current_user, nil)
    ~H"""
    <div class="pipeline">
      <div class="pipeline_header">
        <div class="pipeline_sub_header">
          <h3 class="pipeline_name">{@pipeline.name}</h3>
          <%= if @pipeline[:config_repo_id] do %>
            <span class="text-[10px] text-slate-400 ml-1" title={"Defined by config repo ##{@pipeline.config_repo_id}"}>
              config-repo
            </span>
          <% end %>
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
          <%
            can_operate = ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, @current_user)
            trigger_disabled = @pipeline.paused or not can_operate

            play_class = if trigger_disabled, do: "button pipeline_btn play disabled", else: "button pipeline_btn play"
            play_options_class = if trigger_disabled, do: "button pipeline_btn play_with_options disabled", else: "button pipeline_btn play_with_options"

            pause_unpause_class =
              cond do
                @pipeline.paused and can_operate -> "button pipeline_btn unpause"
                @pipeline.paused -> "button pipeline_btn unpause disabled"
                can_operate -> "button pipeline_btn pause"
                true -> "button pipeline_btn pause disabled"
              end

            pause_title = if @pipeline.paused, do: "Pipeline Paused", else: "Pause Pipeline"
            play_title = if @pipeline.paused, do: "Trigger Pipeline Disabled", else: "Trigger Pipeline"
            play_options_title = if @pipeline.paused, do: "Trigger with Options Disabled", else: "Trigger with Options"
          %>
          <ul class="pipeline_operations">
            <li>
              <button
                type="button"
                aria-label={play_title}
                title={play_title}
                class={play_class}
                phx-click={if not trigger_disabled, do: "trigger_pipeline", else: nil}
                phx-value-name={@pipeline.name}
              >
              </button>
            </li>
            <li>
              <button
                type="button"
                aria-label={play_options_title}
                title={play_options_title}
                class={play_options_class}
              >
              </button>
            </li>
            <li>
              <button
                type="button"
                aria-label={pause_title}
                title={pause_title}
                class={pause_unpause_class}
                phx-click={
                  cond do
                    not can_operate -> nil
                    @pipeline.paused -> "unpause_pipeline"
                    true -> "show_pause_modal"
                  end
                }
                phx-value-name={@pipeline.name}
              >
              </button>
            </li>
          </ul>
          <a href={"/pipeline/activity/#{@pipeline.name}"} class="pipeline_history">History</a>
          <%= if @pipeline.paused do %>
            <div class="pipeline_pause-message">
              Paused by {@pipeline.paused_by || "anonymous"} ({if @pipeline.pause_cause == "", do: "", else: @pipeline.pause_cause})
              <%= if @pipeline.paused_at do %>
                <div title={format_server_time(@pipeline.paused_at)}>on {format_local_time(@pipeline.paused_at)}</div>
              <% end %>
            </div>
          <% end %>
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
              phx-click="show_stage_summary"
              phx-value-pipeline={@pipeline.name}
              phx-value-stage={stage.name}
              phx-value-counter={@pipeline.counter}
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
      "Awaiting" -> "#{base} awaiting"
      "NotRun" -> "#{base} unknown"
      _ -> "#{base} unknown"
    end
  end

  defp stage_title(stage) do
    "#{stage.name} (#{stage.status})"
  end

  defp format_local_time(nil), do: "—"
  defp format_local_time(datetime) do
    Calendar.strftime(datetime, "%d %b, %Y at %H:%M:%S Local Time")
  end

  defp format_server_time(nil), do: "—"
  defp format_server_time(datetime) do
    Calendar.strftime(datetime, "%d %b, %Y at %H:%M:%S +00:00 Server Time")
  end

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end
  defp format_duration(_), do: "—"

  # Status dot — CSS class for coloured circle indicator
  def status_dot_class(job) do
    state = (job[:state] || "unknown") |> String.downcase()
    result = (job[:result] || "unknown") |> String.downcase()

    base = "status-dot"

    cond do
      state in ["building", "preparing", "completing"] -> "#{base} building"
      state in ["scheduled", "assigned"] -> "#{base} scheduled"
      result == "passed" -> "#{base} passed"
      result == "failed" -> "#{base} failed"
      result == "cancelled" -> "#{base} cancelled"
      true -> "#{base} unknown"
    end
  end

  # Accessibility label for screen readers
  def status_dot_label(job) do
    state = (job[:state] || "Unknown") |> String.capitalize()
    result = (job[:result] || "Unknown")

    cond do
      state in ["Building", "Preparing", "Completing"] -> "Status: #{state}"
      state in ["Scheduled", "Assigned"] -> "Status: #{state}, waiting for agent"
      result == "Passed" -> "Status: Passed"
      result == "Failed" -> "Status: Failed"
      result == "Cancelled" -> "Status: Cancelled"
      true -> "Status: #{state}"
    end
  end
end
