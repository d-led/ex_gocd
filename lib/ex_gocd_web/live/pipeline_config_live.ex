defmodule ExGoCDWeb.PipelineConfigLive do
  use ExGoCDWeb, :live_view

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Job, Material, Stage, Task}
  alias ExGoCD.Repo

  @impl true
  def mount(params, _session, socket) do
    pipeline_name = params["pipeline_name"]
    pipeline = Pipelines.get_pipeline_by_name(pipeline_name)

    if is_nil(pipeline) do
      {:ok,
       socket
       |> put_flash(:error, "Pipeline '#{pipeline_name}' not found.")
       |> redirect(to: "/admin/pipelines")}
    else
      {:ok,
       socket
       |> assign(:pipeline, pipeline)
       |> assign(:errors, %{})
       |> assign(:flash_info, nil)
       # Modal controls
       |> assign(:show_add_modal, false)
       |> assign(:modal_type, nil) # :add_stage, :add_job, :add_task, :edit_task, :edit_material
       |> assign(:modal_form, %{})
       |> assign(:modal_errors, %{})}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    sub_path = params["sub_path"] || ["general"]
    pipeline = socket.assigns.pipeline
    pipeline_with_materials = Repo.preload(pipeline, :materials)
    {view_mode, active_stage, active_job} = view_mode_from_path(sub_path, pipeline)

    {:noreply,
     socket
     |> assign(:pipeline, pipeline_with_materials)
     |> assign(:sub_path, sub_path)
     |> assign(:view_mode, view_mode)
     |> assign(:active_stage, active_stage)
     |> assign(:active_job, active_job)
     |> assign(:page_title, "Edit Pipeline #{pipeline.name} - GoCD")}
  end

  defp view_mode_from_path(sub_path, pipeline) do
    case sub_path do
      ["general"] -> {:general, nil, nil}
      ["materials"] -> {:materials, nil, nil}
      ["stages"] -> {:stages, nil, nil}
      ["stages", stage_name, "settings"] ->
        {:stage_settings, find_stage(pipeline, stage_name), nil}
      ["stages", stage_name, "jobs"] ->
        {:stage_jobs, find_stage(pipeline, stage_name), nil}
      ["stages", stage_name, "jobs", job_name, "settings"] ->
        stage = find_stage(pipeline, stage_name)
        {:job_settings, stage, find_job(stage, job_name)}
      ["stages", stage_name, "jobs", job_name, "tasks"] ->
        stage = find_stage(pipeline, stage_name)
        {:job_tasks, stage, find_job(stage, job_name)}
      _ ->
        {:general, nil, nil}
    end
  end

  defp find_stage(pipeline, stage_name) do
    Enum.find(pipeline.stages || [], & &1.name == stage_name)
  end

  defp find_job(nil, _job_name), do: nil

  defp find_job(stage, job_name) do
    Enum.find(stage.jobs || [], & &1.name == job_name)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-page-wrapper min-h-screen bg-[#f4f8f9] text-[#333] font-sans pb-12">
      <!-- Breadcrumb Header -->
      <div class="bg-white border-b border-[#e9edef] px-6 py-4 flex flex-col sm:flex-row justify-between sm:items-center gap-4">
        <div>
          <div class="text-[11px] font-bold text-slate-400 uppercase tracking-wider mb-1">
            <a href="/admin/pipelines" class="hover:text-slate-700">Pipelines</a>
            &gt;
            <span class="text-slate-600">{@pipeline.name}</span>
            <%= if @active_stage do %>
              &gt; Stages &gt; <span class="text-slate-600">{@active_stage.name}</span>
            <% end %>
            <%= if @active_job do %>
              &gt; Jobs &gt; <span class="text-slate-600">{@active_job.name}</span>
            <% end %>
          </div>
          <h1 class="text-lg font-semibold text-[#333]">
            Pipeline Config: <span class="text-[#943a9e]">{@pipeline.name}</span>
          </h1>
        </div>
        <div class="flex gap-2">
          <a href="/admin/pipelines" class="px-3 py-1.5 bg-white border border-slate-350 text-slate-700 rounded text-xs font-semibold hover:bg-slate-50 transition-all">
            Back to pipelines
          </a>
        </div>
      </div>

      <!-- Main Layout: Sidebar + Forms -->
      <div class="max-w-[1400px] mx-auto px-6 py-6 flex flex-col md:flex-row gap-6">
        <!-- Sidebar Navigation -->
        <div class="w-full md:w-64 shrink-0 bg-white border border-[#d6e0e2] rounded shadow-sm overflow-hidden h-fit">
          <div class="bg-[#e7eef0] px-4 py-2.5 border-b border-[#d6e0e2] text-xs font-bold uppercase tracking-wider text-slate-700">
            Navigation
          </div>
          <nav class="divide-y divide-[#e9edef] text-xs">
            <.nav_sidebar_link active={@view_mode == :general} href={"/go/admin/pipelines/#{@pipeline.name}/edit/general"}>
              <i class="fa fa-sliders mr-2"></i> General Settings
            </.nav_sidebar_link>
            <.nav_sidebar_link active={@view_mode == :materials} href={"/go/admin/pipelines/#{@pipeline.name}/edit/materials"}>
              <i class="fa fa-git-alt mr-2"></i> Materials ({@pipeline.materials |> length()})
            </.nav_sidebar_link>
            <.nav_sidebar_link active={@view_mode in [:stages, :stage_settings, :stage_jobs, :job_settings, :job_tasks]} href={"/go/admin/pipelines/#{@pipeline.name}/edit/stages"}>
              <i class="fa fa-cubes mr-2"></i> Stages Config ({@pipeline.stages |> length()})
            </.nav_sidebar_link>
          </nav>

          <!-- Nested Stages Tree View -->
          <%= if @view_mode in [:stages, :stage_settings, :stage_jobs, :job_settings, :job_tasks] do %>
            <div class="bg-slate-50/50 p-4 border-t border-[#d6e0e2] text-xs space-y-3">
              <span class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider">Stages &amp; Jobs</span>
              <ul class="space-y-2">
                <%= for s <- @pipeline.stages || [] do %>
                  <li class="space-y-1">
                    <div class="flex items-center justify-between">
                      <a href={"/go/admin/pipelines/#{@pipeline.name}/edit/stages/#{s.name}/settings"}
                         class={["hover:text-[#943a9e] flex items-center font-medium", if(@active_stage && @active_stage.id == s.id, do: "text-[#943a9e] font-bold", else: "text-slate-600")]}>
                        <i class="fa-regular fa-folder-open mr-1.5 text-slate-400"></i> {s.name}
                      </a>
                      <a href={"/go/admin/pipelines/#{@pipeline.name}/edit/stages/#{s.name}/jobs"} class="text-[10px] text-[#943a9e] hover:underline">Jobs</a>
                    </div>

                    <%= if @active_stage && @active_stage.id == s.id do %>
                      <ul class="pl-4 border-l border-slate-200 ml-2 space-y-1.5 mt-1">
                        <%= for j <- s.jobs || [] do %>
                          <li>
                            <div class="flex items-center justify-between">
                              <a href={"/go/admin/pipelines/#{@pipeline.name}/edit/stages/#{s.name}/jobs/#{j.name}/settings"}
                                 class={["hover:text-[#943a9e] flex items-center", if(@active_job && @active_job.id == j.id, do: "text-[#943a9e] font-bold", else: "text-slate-500")]}>
                                <i class="fa fa-terminal mr-1 text-[10px] text-slate-400"></i> {j.name}
                              </a>
                              <a href={"/go/admin/pipelines/#{@pipeline.name}/edit/stages/#{s.name}/jobs/#{j.name}/tasks"} class="text-[9px] text-slate-400 hover:text-slate-600">Tasks</a>
                            </div>
                          </li>
                        <% end %>
                      </ul>
                    <% end %>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </div>

        <!-- Form Panels -->
        <div class="flex-grow bg-white border border-[#d6e0e2] rounded shadow-sm p-6">
          <%= if @flash_info do %>
            <div class="mb-5 bg-[#dbf1d9] border border-[#a3d7a8] text-[#298a4c] px-4 py-3 rounded flex justify-between items-center text-sm" role="alert">
              <span class="font-medium">{@flash_info}</span>
              <button phx-click="clear_flash" class="text-[#298a4c] hover:text-emerald-900">
                <i class="fa fa-times"></i>
              </button>
            </div>
          <% end %>

          <%= case @view_mode do %>
            <% :general -> %>
              <.general_settings_panel pipeline={@pipeline} errors={@errors} />
            <% :materials -> %>
              <.materials_panel pipeline={@pipeline} />
            <% :stages -> %>
              <.stages_list_panel pipeline={@pipeline} />
            <% :stage_settings -> %>
              <.stage_settings_panel stage={@active_stage} pipeline={@pipeline} errors={@errors} />
            <% :stage_jobs -> %>
              <.stage_jobs_panel stage={@active_stage} pipeline={@pipeline} />
            <% :job_settings -> %>
              <.job_settings_panel job={@active_job} stage={@active_stage} pipeline={@pipeline} errors={@errors} />
            <% :job_tasks -> %>
              <.job_tasks_panel job={@active_job} stage={@active_stage} pipeline={@pipeline} />
          <% end %>
        </div>
      </div>

      <!-- Popups / Modals -->
      <%= if @show_add_modal do %>
        <.modal_layer type={@modal_type} form={@modal_form} errors={@modal_errors} pipeline={@pipeline} active_stage={@active_stage} active_job={@active_job} />
      <% end %>
    </div>
    """
  end

  # --- Nested Panel Renderings ---

  defp general_settings_panel(assigns) do
    ~H"""
    <div>
      <h2 class="text-sm font-bold text-slate-700 border-b border-[#e9edef] pb-3 mb-5">General Settings</h2>
      <form phx-submit="save_general">
        <div class="space-y-4 max-w-xl">
          <div>
            <label class="block text-xs font-bold text-slate-600 mb-1">Pipeline Name</label>
            <input type="text" value={@pipeline.name} disabled class="w-full px-3 py-2 rounded bg-slate-50 border border-[#d6e0e2] text-xs text-slate-500 cursor-not-allowed" />
          </div>

          <div>
            <label class="block text-xs font-bold text-slate-600 mb-1">Pipeline Group</label>
            <input type="text" name="group" value={@pipeline.group} required class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]" />
          </div>

          <div>
            <label class="block text-xs font-bold text-slate-600 mb-1">Label Template</label>
            <input type="text" name="label_template" value={@pipeline.label_template} required class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]" />
            <p class="text-[10px] text-slate-400 mt-0.5">Use ${COUNT} as placeholder for run counter.</p>
          </div>

          <div>
            <label class="block text-xs font-bold text-slate-600 mb-1">Lock Behavior</label>
            <select name="lock_behavior" class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]">
              <option value="none" selected={@pipeline.lock_behavior == "none"}>Unlock when finished / None</option>
              <option value="lockOnFailure" selected={@pipeline.lock_behavior == "lockOnFailure"}>Lock on failure</option>
              <option value="unlockWhenFinished" selected={@pipeline.lock_behavior == "unlockWhenFinished"}>Lock always / unlock when finished</option>
            </select>
          </div>

          <div class="pt-4">
            <button type="submit" class="px-4 py-2 rounded bg-[#943a9e] hover:bg-purple-700 text-white text-xs font-semibold border border-purple-700 shadow-sm transition-all">
              Save Settings
            </button>
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp materials_panel(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center border-b border-[#e9edef] pb-3 mb-5">
        <h2 class="text-sm font-bold text-slate-700">Pipeline Materials</h2>
        <button phx-click="open_add_modal" phx-value-type="add_material" class="px-2.5 py-1 bg-[#943a9e] hover:bg-purple-700 text-white text-[11px] font-bold rounded shadow-sm">
          <i class="fa fa-plus mr-1"></i> Add Material
        </button>
      </div>

      <div class="border border-[#d6e0e2] rounded overflow-hidden">
        <table class="w-full text-left text-xs text-slate-600">
          <thead class="bg-[#e7eef0] text-[10px] font-bold text-slate-500 uppercase border-b border-[#d6e0e2]">
            <tr>
              <th class="px-4 py-3">Material Type</th>
              <th class="px-4 py-3">URL</th>
              <th class="px-4 py-3">Branch</th>
              <th class="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[#e9edef] bg-white">
            <%= for material <- @pipeline.materials || [] do %>
              <tr class="hover:bg-slate-50/50">
                <td class="px-4 py-3 font-bold uppercase text-slate-700">{material.type}</td>
                <td class="px-4 py-3 font-mono text-[11px] text-slate-500">{material.url}</td>
                <td class="px-4 py-3">{material.branch || "master"}</td>
                <td class="px-4 py-3 text-right">
                  <button phx-click="open_edit_material" phx-value-id={material.id} class="text-[#943a9e] hover:underline font-bold mr-3">Edit</button>
                  <button phx-click="delete_material" phx-value-id={material.id} data-confirm="Are you sure you want to remove this material?" class="text-rose-500 hover:underline">Remove</button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp stages_list_panel(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center border-b border-[#e9edef] pb-3 mb-5">
        <h2 class="text-sm font-bold text-slate-700">Stages Config</h2>
        <button phx-click="open_add_modal" phx-value-type="add_stage" class="px-2.5 py-1 bg-[#943a9e] hover:bg-purple-700 text-white text-[11px] font-bold rounded shadow-sm">
          <i class="fa fa-plus mr-1"></i> Add Stage
        </button>
      </div>

      <div class="border border-[#d6e0e2] rounded overflow-hidden">
        <table class="w-full text-left text-xs text-slate-600">
          <thead class="bg-[#e7eef0] text-[10px] font-bold text-slate-500 uppercase border-b border-[#d6e0e2]">
            <tr>
              <th class="px-4 py-3">Stage Name</th>
              <th class="px-4 py-3">Approval Type</th>
              <th class="px-4 py-3">Jobs Count</th>
              <th class="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[#e9edef] bg-white">
            <%= for s <- @pipeline.stages || [] do %>
              <tr class="hover:bg-slate-50/50">
                <td class="px-4 py-3 font-semibold text-slate-700">
                  <a href={"/go/admin/pipelines/#{@pipeline.name}/edit/stages/#{s.name}/settings"} class="text-[#943a9e] hover:underline">
                    {s.name}
                  </a>
                </td>
                <td class="px-4 py-3">{s.approval_type}</td>
                <td class="px-4 py-3">{s.jobs |> length()}</td>
                <td class="px-4 py-3 text-right">
                  <a href={"/go/admin/pipelines/#{@pipeline.name}/edit/stages/#{s.name}/settings"} class="text-[#943a9e] hover:underline font-bold mr-3">Edit Settings</a>
                  <button phx-click="delete_stage" phx-value-id={s.id} data-confirm="Are you sure you want to delete this stage?" class="text-rose-500 hover:underline">Delete</button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp stage_settings_panel(assigns) do
    ~H"""
    <div>
      <h2 class="text-sm font-bold text-slate-700 border-b border-[#e9edef] pb-3 mb-5">Stage: {@stage.name} - Settings</h2>
      <form phx-submit="save_stage">
        <div class="space-y-4 max-w-xl">
          <div>
            <label class="block text-xs font-bold text-slate-600 mb-1">Stage Name <span class="text-rose-500">*</span></label>
            <input type="text" name="name" value={@stage.name} required class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]" />
            <%= if @errors["name"] do %>
              <p class="text-[11px] text-rose-500 mt-1">{@errors["name"]}</p>
            <% end %>
          </div>

          <div>
            <label class="block text-xs font-bold text-slate-600 mb-2">Stage Trigger Type</label>
            <div class="space-y-2 text-xs">
              <label class="flex items-center gap-2 cursor-pointer font-medium text-slate-700">
                <input type="radio" name="approval_type" value="success" checked={@stage.approval_type == "success"} class="radio radio-xs checked:bg-[#943a9e]" />
                On Success (automatic)
              </label>
              <label class="flex items-center gap-2 cursor-pointer font-medium text-slate-700">
                <input type="radio" name="approval_type" value="manual" checked={@stage.approval_type == "manual"} class="radio radio-xs checked:bg-[#943a9e]" />
                Manual Trigger
              </label>
            </div>
          </div>

          <div class="pt-4">
            <button type="submit" class="px-4 py-2 rounded bg-[#943a9e] hover:bg-purple-700 text-white text-xs font-semibold border border-purple-700 shadow-sm transition-all">
              Save Stage Settings
            </button>
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp stage_jobs_panel(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center border-b border-[#e9edef] pb-3 mb-5">
        <h2 class="text-sm font-bold text-slate-700">Jobs in Stage: {@stage.name}</h2>
        <button phx-click="open_add_modal" phx-value-type="add_job" class="px-2.5 py-1 bg-[#943a9e] hover:bg-purple-700 text-white text-[11px] font-bold rounded shadow-sm">
          <i class="fa fa-plus mr-1"></i> Add Job
        </button>
      </div>

      <div class="border border-[#d6e0e2] rounded overflow-hidden">
        <table class="w-full text-left text-xs text-slate-600">
          <thead class="bg-[#e7eef0] text-[10px] font-bold text-slate-500 uppercase border-b border-[#d6e0e2]">
            <tr>
              <th class="px-4 py-3">Job Name</th>
              <th class="px-4 py-3">Resources Required</th>
              <th class="px-4 py-3">Run on All Agents</th>
              <th class="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[#e9edef] bg-white">
            <%= for j <- @stage.jobs || [] do %>
              <tr class="hover:bg-slate-50/50">
                <td class="px-4 py-3 font-semibold text-slate-700">
                  <a href={"/go/admin/pipelines/#{@pipeline.name}/edit/stages/#{@stage.name}/jobs/#{j.name}/settings"} class="text-[#943a9e] hover:underline">
                    {j.name}
                  </a>
                </td>
                <td class="px-4 py-3">
                  <%= if Enum.empty?(j.resources || []) do %>
                    <span class="text-slate-400 italic">None</span>
                  <% else %>
                    <div class="flex gap-1">
                      <%= for r <- j.resources || [] do %>
                        <span class="bg-slate-100 border border-[#d6e0e2] px-1.5 py-0.5 rounded text-[10px] text-slate-600">{r}</span>
                      <% end %>
                    </div>
                  <% end %>
                </td>
                <td class="px-4 py-3">{if j.run_on_all_agents, do: "Yes", else: "No"}</td>
                <td class="px-4 py-3 text-right">
                  <a href={"/go/admin/pipelines/#{@pipeline.name}/edit/stages/#{@stage.name}/jobs/#{j.name}/settings"} class="text-[#943a9e] hover:underline font-bold mr-3">Configure</a>
                  <button phx-click="delete_job" phx-value-id={j.id} data-confirm="Are you sure you want to delete this job?" class="text-rose-500 hover:underline">Delete</button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp job_settings_panel(assigns) do
    ~H"""
    <div>
      <h2 class="text-sm font-bold text-slate-700 border-b border-[#e9edef] pb-3 mb-5">Job: {@job.name} - Settings</h2>
      <form phx-submit="save_job">
        <div class="space-y-4 max-w-xl">
          <div>
            <label class="block text-xs font-bold text-slate-600 mb-1">Job Name <span class="text-rose-500">*</span></label>
            <input type="text" name="name" value={@job.name} required class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]" />
          </div>

          <div>
            <label class="block text-xs font-bold text-slate-600 mb-1">Resources Required (comma-separated)</label>
            <input type="text" name="resources" value={@job.resources |> Enum.join(", ")} placeholder="e.g. linux, docker" class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]" />
          </div>

          <div>
            <label class="block text-xs font-bold text-slate-600 mb-2">Agent Settings</label>
            <label class="flex items-center gap-2 cursor-pointer text-xs font-medium text-slate-700">
              <input type="checkbox" name="run_on_all_agents" value="true" checked={@job.run_on_all_agents} class="checkbox checkbox-xs" />
              Run on all agents
            </label>
          </div>

          <div class="pt-4">
            <button type="submit" class="px-4 py-2 rounded bg-[#943a9e] hover:bg-purple-700 text-white text-xs font-semibold border border-purple-700 shadow-sm transition-all">
              Save Job Settings
            </button>
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp job_tasks_panel(assigns) do
    # Preload tasks
    job = ExGoCD.Repo.preload(assigns.job, :tasks)
    assigns = assign(assigns, :job, job)

    ~H"""
    <div>
      <div class="flex justify-between items-center border-b border-[#e9edef] pb-3 mb-5">
        <h2 class="text-sm font-bold text-slate-700">Tasks in Job: {@job.name}</h2>
        <button phx-click="open_add_modal" phx-value-type="add_task" class="px-2.5 py-1 bg-[#943a9e] hover:bg-purple-700 text-white text-[11px] font-bold rounded shadow-sm">
          <i class="fa fa-plus mr-1"></i> Add Task
        </button>
      </div>

      <div class="border border-[#d6e0e2] rounded overflow-hidden">
        <table class="w-full text-left text-xs text-slate-600">
          <thead class="bg-[#e7eef0] text-[10px] font-bold text-slate-500 uppercase border-b border-[#d6e0e2]">
            <tr>
              <th class="px-4 py-3">Task Type</th>
              <th class="px-4 py-3">Command / Run script</th>
              <th class="px-4 py-3">Arguments</th>
              <th class="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[#e9edef] bg-white">
            <%= for {task, index} <- (@job.tasks || []) |> Enum.with_index() do %>
              <tr class="hover:bg-slate-50/50">
                <td class="px-4 py-3 font-bold uppercase text-[#943a9e]">{task.type}</td>
                <td class="px-4 py-3 font-mono text-[11px] text-slate-700">{task.command}</td>
                <td class="px-4 py-3 font-mono text-[11px] text-slate-400">
                  {task.arguments |> Enum.join(" ")}
                </td>
                <td class="px-4 py-3 text-right">
                  <button phx-click="open_edit_task" phx-value-id={task.id} class="text-[#943a9e] hover:underline font-bold mr-3">Edit</button>
                  <button phx-click="delete_task" phx-value-id={task.id} class="text-rose-500 hover:underline mr-3">Delete</button>

                  <!-- Order sorting -->
                  <%= if index > 0 do %>
                    <button phx-click="move_task" phx-value-id={task.id} phx-value-dir="up" class="p-0.5 border border-slate-200 hover:bg-slate-100 rounded text-[10px] text-slate-500 w-5 h-5 inline-flex items-center justify-center">
                      <i class="fa fa-arrow-up"></i>
                    </button>
                  <% end %>
                  <%= if index < length(@job.tasks) - 1 do %>
                    <button phx-click="move_task" phx-value-id={task.id} phx-value-dir="down" class="p-0.5 border border-slate-200 hover:bg-slate-100 rounded text-[10px] text-slate-500 w-5 h-5 inline-flex items-center justify-center ml-1">
                      <i class="fa fa-arrow-down"></i>
                    </button>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # --- Modal Overlay layer ---

  defp modal_layer(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
      <div class="bg-white rounded border border-[#d6e0e2] shadow-xl w-full max-w-lg overflow-hidden">
        <div class="bg-[#e7eef0] border-b border-[#d6e0e2] px-5 py-3 flex justify-between items-center">
          <h3 class="text-xs font-bold uppercase tracking-wider text-slate-700">
            <%= case @type do %>
              <% :add_stage -> %>Add Stage Configuration
              <% :add_job -> %>Add Job Configuration
              <% :add_task -> %>Add Task Configuration
              <% :edit_task -> %>Edit Task Configuration
              <% :add_material -> %>Add Repository Material
              <% :edit_material -> %>Edit Repository Material
            <% end %>
          </h3>
          <button phx-click="close_modal" class="text-slate-400 hover:text-[#333]">
            <i class="fa fa-times"></i>
          </button>
        </div>

        <form phx-submit="save_modal">
          <div class="p-5 space-y-4 text-xs text-slate-600">
            <%= case @type do %>
              <% :add_stage -> %>
                <div>
                  <label class="block font-bold text-slate-600 mb-1">Stage Name *</label>
                  <input type="text" name="name" required class="w-full px-3 py-2 border border-[#d6e0e2] rounded bg-white text-xs" />
                </div>
                <div>
                  <label class="block font-bold text-slate-600 mb-2">Stage Trigger Type</label>
                  <div class="space-y-2">
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input type="radio" name="approval_type" value="success" checked class="radio radio-xs checked:bg-[#943a9e]" />
                      On Success (automatic)
                    </label>
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input type="radio" name="approval_type" value="manual" class="radio radio-xs checked:bg-[#943a9e]" />
                      Manual Trigger
                    </label>
                  </div>
                </div>

              <% :add_job -> %>
                <div>
                  <label class="block font-bold text-slate-600 mb-1">Job Name *</label>
                  <input type="text" name="name" required class="w-full px-3 py-2 border border-[#d6e0e2] rounded bg-white text-xs" />
                </div>

              <% :add_material -> %>
                <div>
                  <label class="block font-bold text-slate-600 mb-1">Material Type</label>
                  <select name="type" class="w-full px-3 py-2 border border-[#d6e0e2] rounded bg-white text-xs">
                    <option value="git">Git</option>
                    <option value="svn">Subversion</option>
                    <option value="hg">Mercurial</option>
                    <option value="dependency">Pipeline Dependency</option>
                  </select>
                </div>
                <div>
                  <label class="block font-bold text-slate-600 mb-1">Repository URL *</label>
                  <input type="text" name="url" required class="w-full px-3 py-2 border border-[#d6e0e2] rounded bg-white text-xs" />
                </div>
                <div>
                  <label class="block font-bold text-slate-600 mb-1">Branch</label>
                  <input type="text" name="branch" value="master" class="w-full px-3 py-2 border border-[#d6e0e2] rounded bg-white text-xs" />
                </div>

              <% :edit_material -> %>
                <input type="hidden" name="_id" value={@form["id"]} />
                <div>
                  <label class="block font-bold text-slate-600 mb-1">Repository URL *</label>
                  <input type="text" name="url" value={@form["url"]} required class="w-full px-3 py-2 border border-[#d6e0e2] rounded bg-white text-xs" />
                </div>
                <div>
                  <label class="block font-bold text-slate-600 mb-1">Branch</label>
                  <input type="text" name="branch" value={@form["branch"]} class="w-full px-3 py-2 border border-[#d6e0e2] rounded bg-white text-xs" />
                </div>

              <% type when type in [:add_task, :edit_task] -> %>
                <%= if type == :edit_task do %>
                  <input type="hidden" name="_id" value={@form["id"]} />
                <% end %>
                <div>
                  <label class="block font-bold text-slate-600 mb-1">Task Type</label>
                  <select name="type" class="w-full px-3 py-2 border border-[#d6e0e2] rounded bg-white text-xs">
                    <option value="exec" selected={@form["type"] == "exec"}>Exec Task</option>
                    <option value="ant" selected={@form["type"] == "ant"}>Ant</option>
                    <option value="rake" selected={@form["type"] == "rake"}>Rake</option>
                  </select>
                </div>
                <div>
                  <label class="block font-bold text-slate-600 mb-1">Command *</label>
                  <input type="text" name="command" value={@form["command"]} required class="w-full px-3 py-2 border border-[#d6e0e2] rounded bg-white text-xs" />
                </div>
                <div>
                  <label class="block font-bold text-slate-600 mb-1">Arguments</label>
                  <textarea name="arguments" rows="3" class="w-full px-3 py-2 border border-[#d6e0e2] rounded bg-white text-xs font-mono">{@form["arguments"]}</textarea>
                  <p class="text-[10px] text-slate-400 mt-0.5">Enter one argument per line.</p>
                </div>
            <% end %>
          </div>

          <div class="bg-[#f4f8f9] border-t border-[#d6e0e2] px-5 py-3 flex justify-end gap-2">
            <button type="button" phx-click="close_modal" class="px-4 py-2 border border-slate-350 bg-white hover:bg-slate-50 text-slate-700 text-xs font-semibold rounded">
              Cancel
            </button>
            <button type="submit" class="px-4 py-2 bg-[#943a9e] hover:bg-purple-700 text-white text-xs font-semibold rounded border border-purple-700 shadow-sm">
              Save Configuration
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp nav_sidebar_link(assigns) do
    ~H"""
    <a href={@href} class={["block px-4 py-2.5 font-medium border-l-2 hover:bg-slate-50 transition-all",
                            if(@active, do: "border-[#943a9e] text-[#943a9e] bg-purple-50/20 font-bold",
                                       else: "border-transparent text-slate-600 hover:text-[#333]")]}>
      {render_slot(@inner_block)}
    </a>
    """
  end

  # --- Event Handlers ---

  @impl true
  def handle_event("clear_flash", _params, socket) do
    {:noreply, assign(socket, :flash_info, nil)}
  end

  @impl true
  def handle_event("save_general", params, socket) do
    group = params["group"]
    label_template = params["label_template"]
    lock_behavior = params["lock_behavior"]
    pipeline = socket.assigns.pipeline
    case Pipelines.update_pipeline(pipeline, %{
      group: group,
      label_template: label_template,
      lock_behavior: lock_behavior
    }) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:pipeline, updated)
         |> assign(:flash_info, "Pipeline settings updated successfully.")}
      {:error, _changeset} ->
        {:noreply, assign(socket, :flash_info, "Error updating pipeline configuration.")}
    end
  end

  @impl true
  def handle_event("save_stage", params, socket) do
    name = params["name"]
    approval_type = params["approval_type"] || "success"
    stage = socket.assigns.active_stage
    case Pipelines.update_stage(stage, %{name: name, approval_type: approval_type}) do
      {:ok, _updated} ->
        # Reload pipeline to refresh tree
        pipeline = Pipelines.get_pipeline_by_name!(socket.assigns.pipeline.name)
        {:noreply,
         socket
         |> assign(:pipeline, pipeline)
         |> assign(:flash_info, "Stage updated successfully.")
         |> push_patch(to: "/go/admin/pipelines/#{pipeline.name}/edit/stages/#{name}/settings")}
      {:error, _changeset} ->
        {:noreply, assign(socket, :flash_info, "Error updating stage.")}
    end
  end

  @impl true
  def handle_event("save_job", params, socket) do
    name = params["name"]
    resources = params["resources"] || ""
    run_on_all_agents = params["run_on_all_agents"]

    resources_list =
      resources
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    run_on_all_agents_bool = run_on_all_agents == "true"
    job = socket.assigns.active_job

    case Pipelines.update_job(job, %{
      name: name,
      resources: resources_list,
      run_on_all_agents: run_on_all_agents_bool
    }) do
      {:ok, _updated} ->
        pipeline = Pipelines.get_pipeline_by_name!(socket.assigns.pipeline.name)
        {:noreply,
         socket
         |> assign(:pipeline, pipeline)
         |> assign(:flash_info, "Job configuration updated successfully.")
         |> push_patch(to: "/go/admin/pipelines/#{pipeline.name}/edit/stages/#{socket.assigns.active_stage.name}/jobs/#{name}/settings")}
      {:error, _changeset} ->
        {:noreply, assign(socket, :flash_info, "Error updating job.")}
    end
  end

  # --- Modal Controls ---

  @impl true
  def handle_event("open_add_modal", %{"type" => type}, socket) do
    modal_type = String.to_existing_atom(type)
    {:noreply,
     socket
     |> assign(:show_add_modal, true)
     |> assign(:modal_type, modal_type)
     |> assign(:modal_form, %{"type" => "exec", "command" => "", "arguments" => ""})}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_modal, false)
     |> assign(:modal_type, nil)
     |> assign(:modal_form, %{})}
  end

  @impl true
  def handle_event("open_edit_task", %{"id" => id}, socket) do
    task = Pipelines.get_task(id)
    {:noreply,
     socket
     |> assign(:show_add_modal, true)
     |> assign(:modal_type, :edit_task)
     |> assign(:modal_form, %{
       "id" => task.id,
       "type" => task.type,
       "command" => task.command,
       "arguments" => task.arguments |> Enum.join("\n")
     })}
  end

  @impl true
  def handle_event("open_edit_material", %{"id" => id}, socket) do
    # Fetch material
    material = Repo.get(Material, id)
    {:noreply,
     socket
     |> assign(:show_add_modal, true)
     |> assign(:modal_type, :edit_material)
     |> assign(:modal_form, %{
       "id" => material.id,
       "url" => material.url,
       "branch" => material.branch
     })}
  end

  @impl true
  def handle_event("delete_stage", %{"id" => id}, socket) do
    stage = Repo.get(Stage, id)
    if stage do
      {:ok, _} = Pipelines.delete_stage(stage)
    end
    pipeline = Pipelines.get_pipeline_by_name!(socket.assigns.pipeline.name)
    {:noreply,
     socket
     |> assign(:pipeline, pipeline)
     |> assign(:flash_info, "Stage was deleted successfully.")}
  end

  @impl true
  def handle_event("delete_job", %{"id" => id}, socket) do
    job = Repo.get(Job, id)
    if job do
      {:ok, _} = Pipelines.delete_job(job)
    end
    pipeline = Pipelines.get_pipeline_by_name!(socket.assigns.pipeline.name)
    {:noreply,
     socket
     |> assign(:pipeline, pipeline)
     |> assign(:flash_info, "Job was deleted successfully.")}
  end

  @impl true
  def handle_event("delete_material", %{"id" => id}, socket) do
    material = Repo.get(Material, id)
    if material do
      # Remove associations
      pipeline = socket.assigns.pipeline |> Repo.preload(:materials)
      updated_materials = Enum.reject(pipeline.materials, &(&1.id == material.id))

      pipeline
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:materials, updated_materials)
      |> Repo.update()
    end
    pipeline = Pipelines.get_pipeline_by_name!(socket.assigns.pipeline.name)
    {:noreply,
     socket
     |> assign(:pipeline, pipeline)
     |> assign(:flash_info, "Material removed successfully.")}
  end

  @impl true
  def handle_event("delete_task", %{"id" => id}, socket) do
    task = Repo.get(Task, id)
    if task do
      {:ok, _} = Pipelines.delete_task(task)
    end
    {:noreply,
     socket
     |> reload_pipeline_and_stage()
     |> assign(:flash_info, "Task deleted successfully.")}
  end

  @impl true
  def handle_event("move_task", %{"id" => id, "dir" => dir}, socket) do
    task = Repo.get!(Task, id)
    job = Pipelines.get_job(task.job_id)

    # We sort tasks based on ID or order. Let's find index in current list:
    tasks = job.tasks |> Enum.sort_by(& &1.id)
    index = Enum.find_index(tasks, & &1.id == task.id)

    swap_index = if dir == "up", do: index - 1, else: index + 1

    if swap_index >= 0 and swap_index < length(tasks) do
      # Swap task content in DB to represent order swap (simple database ID swap or simple execution order swap)
      # Since we don't have a separate 'position' field, let's swap the command/args details of the tasks!
      task_a = Enum.at(tasks, index)
      task_b = Enum.at(tasks, swap_index)

      attrs_a = %{type: task_b.type, command: task_b.command, arguments: task_b.arguments}
      attrs_b = %{type: task_a.type, command: task_a.command, arguments: task_a.arguments}

      Repo.transaction(fn ->
        task_a |> Task.changeset(attrs_a) |> Repo.update!()
        task_b |> Task.changeset(attrs_b) |> Repo.update!()
      end)
    end

    {:noreply,
     socket
     |> reload_pipeline_and_stage()
     |> assign(:flash_info, "Task reordered successfully.")}
  end

  @impl true
  def handle_event("save_modal", params, socket) do
    case save_modal_result(params, socket) do
      {:ok, updated_socket} ->
        {:noreply, updated_socket}

      {:error, {:circular_dependency, path}} ->
        path_str = Enum.join(path, " -> ")
        {:noreply, assign(socket, :flash_info, "Error: Circular dependency detected (#{path_str})")}

      {:error, {:missing_pipeline, name}} ->
        {:noreply, assign(socket, :flash_info, "Error: Referenced pipeline '#{name}' does not exist")}

      {:error, _reason} ->
        {:noreply, assign(socket, :flash_info, "Error saving configuration: invalid values provided.")}
    end
  end

  defp reload_pipeline_and_stage(socket) do
    pipeline = Pipelines.get_pipeline_by_name!(socket.assigns.pipeline.name)
    active_stage = Enum.find(pipeline.stages || [], & &1.name == socket.assigns.active_stage.name)
    active_job = if active_stage, do: Enum.find(active_stage.jobs || [], & &1.name == socket.assigns.active_job.name)

    socket
    |> assign(:pipeline, pipeline)
    |> assign(:active_stage, active_stage)
    |> assign(:active_job, active_job)
  end

  defp save_modal_result(params, socket) do
    case save_modal_change(params, socket) do
      {:ok, _} -> {:ok, reload_saved_pipeline(socket)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp save_modal_change(params, socket) do
    save_modal_for_type(socket.assigns.modal_type, params, socket)
  end

  defp save_modal_for_type(:add_stage, params, socket) do
    Pipelines.create_stage(%{
      name: params["name"],
      approval_type: params["approval_type"] || "success",
      pipeline_id: socket.assigns.pipeline.id
    })
  end

  defp save_modal_for_type(:add_job, params, socket) do
    Pipelines.create_job(%{
      name: params["name"],
      stage_id: socket.assigns.active_stage.id
    })
  end

  defp save_modal_for_type(:add_task, params, socket) do
    Pipelines.create_task(%{
      type: params["type"] || "exec",
      command: params["command"],
      arguments: parse_arguments(params["arguments"]),
      job_id: socket.assigns.active_job.id
    })
  end

  defp save_modal_for_type(:edit_task, params, _socket) do
    task_id = params["_id"] || params["id"]
    task = Repo.get!(Task, task_id)

    Pipelines.update_task(task, %{
      type: params["type"] || "exec",
      command: params["command"],
      arguments: parse_arguments(params["arguments"])
    })
  end

  defp save_modal_for_type(:add_material, params, socket) do
    Pipelines.create_material_for_pipeline(socket.assigns.pipeline, material_attributes(params))
  end

  defp save_modal_for_type(:edit_material, params, _socket) do
    material_id = params["_id"] || params["id"]
    material = Repo.get!(Material, material_id)

    Pipelines.update_material(material, %{
      url: params["url"],
      branch: params["branch"]
    })
  end

  defp save_modal_for_type(_modal_type, _params, _socket), do: {:error, :unsupported_modal}

  defp parse_arguments(arguments) do
    (arguments || "")
    |> String.split(["\n", "\r\n"], trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp material_attributes(params) do
    %{
      "type" => params["type"] || "git",
      "url" => params["url"],
      "branch" => params["branch"] || "master"
    }
  end

  defp reload_saved_pipeline(socket) do
    pipeline = socket.assigns.pipeline
    stage = socket.assigns.active_stage
    job = socket.assigns.active_job

    new_pipeline = Pipelines.get_pipeline_by_name!(pipeline.name)
    new_stage = if stage, do: Enum.find(new_pipeline.stages || [], &(&1.name == stage.name))
    new_job = if new_stage && job, do: Enum.find(new_stage.jobs || [], &(&1.name == job.name))

    socket
    |> assign(:pipeline, new_pipeline)
    |> assign(:active_stage, new_stage)
    |> assign(:active_job, new_job)
    |> assign(:show_add_modal, false)
    |> assign(:modal_type, nil)
    |> assign(:flash_info, "Configuration saved successfully.")
  end
end
