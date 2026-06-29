# Copyright 2026 ex_gocd
# LiveView for GoCD Job Details page showing console logs and artifacts.

defmodule ExGoCDWeb.JobDetailsLive do
  use ExGoCDWeb, :live_view

  import Ecto.Query

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents
  alias ExGoCD.Pipelines.JobInstance
  alias ExGoCD.Repo
  alias ExGoCD.Pipelines.PipelineMaterialRevision

  @impl true
  def mount(params, _session, socket) do
    pipeline_name = params["pipeline_name"]
    pipeline_counter = String.to_integer(params["pipeline_counter"])
    stage_name = params["stage_name"]
    stage_counter = String.to_integer(params["stage_counter"])
    job_name = params["job_name"]

    run =
      get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)
      |> ensure_run(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)

    job_instance =
      get_job_instance(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)
      |> ensure_job_instance(pipeline_name, stage_name, stage_counter, job_name)

    {initial_lines, line_count, fold_stack, fold_counter} = prepare_initial_log(run)

    if connected?(socket) && run && Map.get(run, :build_id) do
      AgentJobRuns.subscribe_console(run.build_id)
    end

    artifacts =
      list_artifacts(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)

    materials = list_materials(pipeline_name, pipeline_counter)

    agent = resolve_agent(job_instance)

    {:ok,
     socket
     |> assign(:pipeline_name, pipeline_name)
     |> assign(:pipeline_counter, pipeline_counter)
     |> assign(:stage_name, stage_name)
     |> assign(:stage_counter, stage_counter)
     |> assign(:job_name, job_name)
     |> assign(:job_instance, job_instance)
     |> assign(:run, run)
     |> assign(:active_tab, "console")
     |> assign(:artifacts, artifacts)
     |> assign(:materials, materials)
     |> assign(:agent, agent)
     |> assign(:show_timestamps, false)
     |> assign(:follow, true)
     |> assign(:wrap_lines, true)
     |> assign(:fold_stack, fold_stack)
     |> assign(:fold_counter, fold_counter)
     |> assign(:line_count, line_count)
     |> assign(:pending_line, "")
     |> assign(:page_title, "Job Details: #{job_name}")
     |> stream(:log_lines, initial_lines, limit: -1000)}
  end

  defp ensure_run(nil, pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    %{
      build_id: nil,
      pipeline_name: pipeline_name,
      pipeline_counter: pipeline_counter,
      stage_name: stage_name,
      stage_counter: stage_counter,
      job_name: job_name,
      state: "Scheduled",
      result: "Unknown",
      console_log: nil
    }
  end

  defp ensure_run(run, _pn, _pc, _sn, _sc, _jn), do: run

  defp ensure_job_instance(nil, pipeline_name, stage_name, stage_counter, job_name) do
    %{
      name: job_name,
      state: "Scheduled",
      result: "Unknown",
      stage_instance: %{
        stage_name: stage_name,
        stage_counter: stage_counter,
        artifacts_deleted: false,
        pipeline_instance: %{pipeline: %{name: pipeline_name}}
      }
    }
  end

  defp ensure_job_instance(job_instance, _pn, _sn, _sc, _jn), do: job_instance

  defp prepare_initial_log(run) do
    log_content = if is_map(run), do: Map.get(run, :console_log) || "", else: ""
    {lines, _next_idx, fold_stack, fold_counter} = parse_log_into_lines(log_content, [], 0)
    line_count = length(lines)
    initial_lines = if line_count > 1000, do: Enum.drop(lines, line_count - 1000), else: lines
    {initial_lines, line_count, fold_stack, fold_counter}
  end

  defp resolve_agent(%JobInstance{agent_uuid: uuid}) when is_binary(uuid),
    do: Agents.get_agent_by_uuid(uuid)

  defp resolve_agent(%{agent_uuid: uuid}) when is_binary(uuid),
    do: Agents.get_agent_by_uuid(uuid)

  defp resolve_agent(_job_instance), do: nil

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("toggle_artifact_dir", %{"path" => dir_path}, socket) do
    artifacts = toggle_dir(socket.assigns.artifacts, dir_path)
    {:noreply, assign(socket, artifacts: artifacts)}
  end

  @impl true
  def handle_event("toggle_timestamps", _params, socket) do
    {:noreply, assign(socket, :show_timestamps, !socket.assigns.show_timestamps)}
  end

  @impl true
  def handle_event("toggle_follow", _params, socket) do
    {:noreply, assign(socket, :follow, !socket.assigns.follow)}
  end

  @impl true
  def handle_event("toggle_wrap", _params, socket) do
    {:noreply, assign(socket, :wrap_lines, !socket.assigns.wrap_lines)}
  end

  defp toggle_dir(items, target_path) do
    Enum.map(items, fn
      %{type: :directory, rel_path: ^target_path} = dir ->
        %{dir | expanded: !dir.expanded}

      %{type: :directory, children: children} = dir ->
        %{dir | children: toggle_dir(children, target_path)}

      other ->
        other
    end)
  end

  @impl true
  def handle_info({:console_append, chunk}, socket) do
    run = socket.assigns.run

    if run do
      new_console_log = (run.console_log || "") <> chunk
      updated_run = %{run | console_log: new_console_log}

      text = socket.assigns.pending_line <> chunk
      lines_raw = String.split(text, "\n")
      {completed_lines, [new_pending]} = Enum.split(lines_raw, -1)

      line_count = socket.assigns.line_count
      fold_stack = socket.assigns.fold_stack
      fold_counter = socket.assigns.fold_counter

      {indexed_lines, _next_idx, new_stack, new_counter} =
        parse_and_accumulate_lines(completed_lines, line_count, fold_stack, fold_counter)

      {:noreply,
       socket
       |> assign(run: updated_run)
       |> assign(pending_line: new_pending)
       |> assign(line_count: line_count + length(completed_lines))
       |> assign(fold_stack: new_stack)
       |> assign(fold_counter: new_counter)
       |> stream(:log_lines, indexed_lines, limit: -1000)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:run_updated, updated_run}, socket) do
    if socket.assigns.run && updated_run.build_id == socket.assigns.run.build_id do
      old_state = socket.assigns.run.state
      new_state = updated_run.state

      socket =
        if old_state in ["Scheduled", "Assigned", "Preparing"] and
             new_state not in ["Scheduled", "Assigned", "Preparing"] do
          {lines, _next_idx, fold_stack, fold_counter} =
            parse_log_into_lines(updated_run.console_log, [], 0)

          line_count = length(lines)

          initial_lines =
            if line_count > 1000, do: Enum.drop(lines, line_count - 1000), else: lines

          socket
          |> assign(line_count: line_count)
          |> assign(fold_stack: fold_stack)
          |> assign(fold_counter: fold_counter)
          |> assign(pending_line: "")
          |> stream(:log_lines, initial_lines, reset: true, limit: -1000)
        else
          socket
        end

      {:noreply, assign(socket, run: updated_run)}
    else
      # Re-fetch run if it was just created/assigned
      run =
        get_run_by_params(
          socket.assigns.pipeline_name,
          socket.assigns.pipeline_counter,
          socket.assigns.stage_name,
          socket.assigns.stage_counter,
          socket.assigns.job_name
        )

      if run && connected?(socket) do
        AgentJobRuns.subscribe_console(run.build_id)
      end

      {lines, fold_stack, fold_counter} =
        if run do
          {l, _idx, s, c} = parse_log_into_lines(run.console_log, [], 0)
          {l, s, c}
        else
          {[], [], 0}
        end

      line_count = length(lines)
      initial_lines = if line_count > 1000, do: Enum.drop(lines, line_count - 1000), else: lines

      {:noreply,
       socket
       |> assign(run: run)
       |> assign(line_count: line_count)
       |> assign(fold_stack: fold_stack)
       |> assign(fold_counter: fold_counter)
       |> assign(pending_line: "")
       |> stream(:log_lines, initial_lines, reset: true, limit: -1000)}
    end
  end

  defp parse_log_into_lines(nil, stack, counter), do: {[], 0, stack, counter}

  defp parse_log_into_lines(log, stack, counter) when is_binary(log) do
    raw_lines =
      log
      |> String.replace("\r\n", "\n")
      |> String.trim_trailing("\n")
      |> String.split("\n")

    parse_and_accumulate_lines(raw_lines, 0, stack, counter)
  end

  defp parse_and_accumulate_lines(raw_lines, start_idx, fold_stack, fold_counter) do
    Enum.reduce(raw_lines, {[], start_idx, fold_stack, fold_counter}, fn line_text,
                                                                         {acc, idx, stack,
                                                                          counter} ->
      parsed = parse_line(line_text, idx)
      msg = parsed.message || ""
      {line_type, fold_name} = detect_fold(msg)

      {new_stack, new_counter, line_record} =
        case line_type do
          :fold_start ->
            fold_id = "fold-#{counter + 1}"
            parent = List.first(stack)

            record = %{
              id: to_string(idx),
              timestamp: parsed.timestamp,
              message: parsed.message,
              formatted_message: format_line_message(parsed.message),
              type: :fold_start,
              fold_id: fold_id,
              fold_name: fold_name,
              parent_fold_id: parent,
              fold_parents: Enum.reverse(stack) |> Enum.join(" ")
            }

            {[fold_id | stack], counter + 1, record}

          :fold_end ->
            case stack do
              [current_fold | rest] ->
                record = %{
                  id: to_string(idx),
                  timestamp: parsed.timestamp,
                  message: parsed.message,
                  formatted_message: format_line_message(parsed.message),
                  type: :fold_end,
                  fold_id: current_fold,
                  parent_fold_id: List.first(rest),
                  fold_parents: Enum.reverse(rest) |> Enum.join(" ")
                }

                {rest, counter, record}

              [] ->
                record = %{
                  id: to_string(idx),
                  timestamp: parsed.timestamp,
                  message: parsed.message,
                  formatted_message: format_line_message(parsed.message),
                  type: :normal,
                  fold_id: nil,
                  parent_fold_id: nil,
                  fold_parents: ""
                }

                {[], counter, record}
            end

          :none ->
            parent = List.first(stack)

            record = %{
              id: to_string(idx),
              timestamp: parsed.timestamp,
              message: parsed.message,
              formatted_message: format_line_message(parsed.message),
              type: :normal,
              fold_id: nil,
              parent_fold_id: parent,
              fold_parents: Enum.reverse(stack) |> Enum.join(" ")
            }

            {stack, counter, record}
        end

      {[line_record | acc], idx + 1, new_stack, new_counter}
    end)
    |> then(fn {acc, idx, stack, counter} -> {Enum.reverse(acc), idx, stack, counter} end)
  end

  defp detect_fold(message_text) do
    cond do
      String.contains?(message_text, "##[fold]") ->
        case String.split(message_text, "##[fold]") do
          [_, fold_name] -> {:fold_start, strip_ansi(fold_name)}
          _ -> {:none, nil}
        end

      String.contains?(message_text, "##[endfold]") ->
        {:fold_end, nil}

      true ->
        {:none, nil}
    end
  end

  defp strip_ansi(text) do
    text
    |> String.replace(~r{\e\[[0-9;]*m}, "")
    |> String.trim()
  end

  defp parse_line(
         <<h1, h2, ?:, m1, m2, ?:, s1, s2, ?., ms1, ms2, ms3, ?\s, message::binary>>,
         id
       )
       when h1 in 48..57 and h2 in 48..57 and
              m1 in 48..57 and m2 in 48..57 and
              s1 in 48..57 and s2 in 48..57 and
              ms1 in 48..57 and ms2 in 48..57 and ms3 in 48..57 do
    timestamp = <<h1, h2, ?:, m1, m2, ?:, s1, s2, ?., ms1, ms2, ms3>>
    %{id: to_string(id), timestamp: timestamp, message: message}
  end

  defp parse_line(line_text, id) do
    %{id: to_string(id), timestamp: nil, message: line_text}
  end

  # Helpers

  defp get_job_instance(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    JobInstance
    |> join(:inner, [ji], si in assoc(ji, :stage_instance))
    |> join(:inner, [ji, si], pi in assoc(si, :pipeline_instance))
    |> join(:inner, [ji, si, pi], p in assoc(pi, :pipeline))
    |> where(
      [ji, si, pi, p],
      p.name == ^pipeline_name and
        pi.counter == ^pipeline_counter and
        si.name == ^stage_name and
        si.counter == ^stage_counter and
        ji.name == ^job_name
    )
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(stage_instance: [pipeline_instance: :pipeline])
  end

  defp get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    AgentJobRuns.get_run_by_params(
      pipeline_name,
      pipeline_counter,
      stage_name,
      stage_counter,
      job_name
    )
  end

  defp artifacts_dir do
    System.get_env("ARTIFACTS_DIR") || "artifacts"
  end

  defp list_artifacts(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    job_dir =
      Path.join([
        artifacts_dir(),
        pipeline_name,
        to_string(pipeline_counter),
        stage_name,
        to_string(stage_counter),
        job_name
      ])

    if File.dir?(job_dir) do
      list_files_recursive(job_dir, job_dir)
    else
      []
    end
  end

  defp list_files_recursive(dir, base_dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.map(&process_file_item(&1, dir, base_dir))
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp process_file_item(name, dir, base_dir) do
    path = Path.join(dir, name)
    rel_path = Path.relative_to(path, base_dir)

    if File.dir?(path) do
      children = list_files_recursive(path, base_dir)
      %{name: name, type: :directory, rel_path: rel_path, children: children, expanded: false}
    else
      file_stat_item(name, rel_path, path)
    end
  end

  defp file_stat_item(name, rel_path, path) do
    case File.stat(path) do
      {:ok, stat} -> %{name: name, type: :file, rel_path: rel_path, size: stat.size}
      _ -> nil
    end
  end

  @doc """
  Renders an artifact tree node recursively.
  """
  def render_artifact_node(%{type: :directory} = assigns) do
    ~H"""
    <div class="artifact-dir">
      <button
        phx-click="toggle_artifact_dir"
        phx-value-path={@rel_path}
        class="flex items-center gap-2 w-full text-left hover:bg-gray-50 px-4 py-2 border-b border-gray-100"
      >
        <i class={[
          "fa text-yellow-500 w-4 text-center transition-transform",
          if(@expanded, do: "fa-caret-down", else: "fa-caret-right")
        ]}>
        </i>
        <i class="fa-solid fa-folder text-yellow-500"></i>
        <span class="font-bold text-gray-800 font-mono text-xs">{@name}</span>
      </button>
      <div class={["ml-6 border-l border-gray-200", !@expanded && "hidden"]}>
        <%= for child <- @children do %>
          <%= if child do %>
            <.render_artifact_node {child} />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  def render_artifact_node(%{type: :file} = assigns) do
    ~H"""
    <div class="flex items-center gap-2 px-4 py-2 border-b border-gray-100 hover:bg-gray-50 font-mono text-xs">
      <i class="fa-solid fa-file-lines text-blue-400 w-4 text-center"></i>
      <span class="flex-1 text-gray-700">{@name}</span>
      <span class="text-gray-400">{format_size(@size)}</span>
      <a
        href={"/files/#{@pipeline_name}/#{@pipeline_counter}/#{@stage_name}/#{@stage_counter}/#{@job_name}/#{@rel_path}"}
        target="_blank"
        class="text-[#2d6ca2] hover:underline font-bold"
      >
        <i class="fa fa-download mr-1"></i> Download
      </a>
    </div>
    """
  end

  def format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  def format_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  def has_test_report?(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    job_dir =
      Path.join([
        artifacts_dir(),
        pipeline_name,
        to_string(pipeline_counter),
        stage_name,
        to_string(stage_counter),
        job_name
      ])

    ExGoCD.TestReport.exists?(job_dir)
  end

  def test_report_url(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    "/files/#{pipeline_name}/#{pipeline_counter}/#{stage_name}/#{stage_counter}/#{job_name}/testoutput/index.html"
  end

  def console_with_links(log) do
    ExGoCDWeb.ConsoleLogHelper.format_log(log)
  end

  defp format_line_message(nil), do: nil
  defp format_line_message(msg), do: ExGoCDWeb.ConsoleLogHelper.format_log(msg)

  def failure_reason(job_instance) do
    state = job_instance[:state] || "Unknown"
    result = job_instance[:result] || "Unknown"

    cond do
      state == "Scheduled" and result == "Failed" ->
        "Job was scheduled but never started. Check if an agent matching the required resources (#{job_resource_summary(job_instance)}) is available and enabled."

      state == "Assigned" and result == "Failed" ->
        "Job was assigned to an agent but failed to start. The agent may have lost connectivity or the working directory was invalid."

      state == "Cancelled" ->
        "Job was cancelled manually or by the system."

      result == "Failed" ->
        "Job completed with failure. Check the console log above for error details."

      true ->
        "Job state: #{state}, result: #{result}."
    end
  end

  defp job_resource_summary(job_instance) do
    # Try to get resources from the job config
    job_name = job_instance[:name]

    if job_name do
      case ExGoCD.Repo.get_by(ExGoCD.Pipelines.Job, name: job_name) do
        nil ->
          "none"

        job ->
          if Enum.empty?(job.resources || []), do: "none", else: Enum.join(job.resources, ", ")
      end
    else
      "unknown"
    end
  end

  defp list_materials(pipeline_name, pipeline_counter) do
    query =
      from(pi in ExGoCD.Pipelines.PipelineInstance,
        join: p in assoc(pi, :pipeline),
        where: p.name == ^pipeline_name and pi.counter == ^pipeline_counter,
        select: pi.id,
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        []

      pi_id ->
        pmrs =
          Repo.all(
            from(pmr in PipelineMaterialRevision,
              join: m in assoc(pmr, :material),
              left_join: mod in assoc(pmr, :modification),
              where: pmr.pipeline_instance_id == ^pi_id,
              select: %{
                url: m.url,
                type: m.type,
                branch: m.branch,
                revision: mod.revision,
                comment: mod.comment,
                modified_at: mod.modified_time
              }
            )
          )

        Enum.map(pmrs, fn r ->
          %{
            name: r.url || "unknown",
            type: r.type || "git",
            revision: if(r.revision, do: String.slice(r.revision, 0, 12) <> "...", else: "—"),
            comment: r.comment || "—",
            modified_at: r.modified_at || "—"
          }
        end)
    end
  end
end
