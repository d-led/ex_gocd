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

    job_instance = get_job_instance(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)
    run = get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)

    use_mock = is_nil(run)

    run =
      if use_mock do
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
      else
        run
      end

    job_instance =
      if is_nil(job_instance) do
        %{
          name: job_name,
          state: "Scheduled",
          result: "Unknown",
          stage_instance: %{
            stage_name: stage_name,
            stage_counter: stage_counter,
            artifacts_deleted: false,
            pipeline_instance: %{
              pipeline: %{
                name: pipeline_name
              }
            }
          }
        }
      else
        job_instance
      end

    if connected?(socket) && run && Map.get(run, :build_id) do
      AgentJobRuns.subscribe_console(run.build_id)
    end

    artifacts = list_artifacts(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)
    materials = list_materials(pipeline_name, pipeline_counter)

    agent = cond do
      is_struct(job_instance, JobInstance) && job_instance.agent_uuid ->
        Agents.get_agent_by_uuid(job_instance.agent_uuid)
      is_map(job_instance) && job_instance[:agent_uuid] ->
        Agents.get_agent_by_uuid(job_instance[:agent_uuid])
      true -> nil
    end

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
     |> assign(:page_title, "Job Details: #{job_name}")}
  end

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

  defp toggle_dir(items, target_path) do
    Enum.map(items, fn
      %{type: :directory, rel_path: ^target_path} = dir ->
        %{dir | expanded: !dir.expanded}

      %{type: :directory, children: children} = dir ->
        %{dir | children: toggle_dir(children, target_path)}

      other -> other
    end)
  end
  @impl true
  def handle_info({:console_append, chunk}, socket) do
    run = socket.assigns.run
    if run do
      new_console_log = (run.console_log || "") <> chunk
      updated_run = %{run | console_log: new_console_log}
      {:noreply, assign(socket, run: updated_run)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:run_updated, updated_run}, socket) do
    if socket.assigns.run && updated_run.build_id == socket.assigns.run.build_id do
      {:noreply, assign(socket, run: updated_run)}
    else
      # Re-fetch run if it was just created/assigned
      run = get_run_by_params(
        socket.assigns.pipeline_name,
        socket.assigns.pipeline_counter,
        socket.assigns.stage_name,
        socket.assigns.stage_counter,
        socket.assigns.job_name
      )
      if run && connected?(socket) do
        AgentJobRuns.subscribe_console(run.build_id)
      end
      {:noreply, assign(socket, run: run)}
    end
  end

  # Helpers

  defp get_job_instance(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    JobInstance
    |> join(:inner, [ji], si in assoc(ji, :stage_instance))
    |> join(:inner, [ji, si], pi in assoc(si, :pipeline_instance))
    |> join(:inner, [ji, si, pi], p in assoc(pi, :pipeline))
    |> where([ji, si, pi, p], p.name == ^pipeline_name and
                              pi.counter == ^pipeline_counter and
                              si.name == ^stage_name and
                              si.counter == ^stage_counter and
                              ji.name == ^job_name)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(stage_instance: [pipeline_instance: :pipeline])
  end

  defp get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    AgentJobRuns.get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)
  end

  defp artifacts_dir do
    System.get_env("ARTIFACTS_DIR") || "artifacts"
  end

  defp list_artifacts(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    job_dir = Path.join([
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
        <i class={["fa text-yellow-500 w-4 text-center transition-transform",
          if(@expanded, do: "fa-caret-down", else: "fa-caret-right")]}></i>
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
    job_dir = Path.join([
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

  def console_with_links(nil), do: ""
  def console_with_links(log) when is_binary(log) do
    ~r{(https?://\S+)}
    |> Regex.replace(log, ~S|<a href="\1" target="_blank" rel="noopener" class="text-cyan-400 underline hover:text-cyan-300">\1</a>|)
    |> Phoenix.HTML.raw()
  end

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
        nil -> "none"
        job -> if Enum.empty?(job.resources || []), do: "none", else: Enum.join(job.resources, ", ")
      end
    else
      "unknown"
    end
  end

  defp list_materials(pipeline_name, pipeline_counter) do
    query = from(pi in ExGoCD.Pipelines.PipelineInstance,
      join: p in assoc(pi, :pipeline),
      where: p.name == ^pipeline_name and pi.counter == ^pipeline_counter,
      select: pi.id,
      limit: 1
    )

    case Repo.one(query) do
      nil -> []
      pi_id ->
        pmrs = Repo.all(
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
