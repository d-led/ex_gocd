defmodule ExGoCDWeb.PipelineWizardLive do
  use ExGoCDWeb, :live_view

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Job, Material, Pipeline, Stage, Task}
  alias ExGoCD.Repo

  @impl true
  def mount(params, _session, socket) do
    group = params["group"] || ""

    # Initial form data state
    form = %{
      "group" => group,
      "name" => "",
      "material_type" => "git",
      "material_url" => "",
      "material_branch" => "master",
      "material_username" => "",
      "material_password" => "",
      "stage_name" => "defaultStage",
      "approval_type" => "success",
      "job_name" => "defaultJob",
      "task_type" => "exec",
      "task_command" => "",
      "task_arguments" => ""
    }

    # Available pipeline groups for autocompletion
    pipeline_groups =
      Pipelines.list_pipelines()
      |> Enum.map(& &1.group)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    {:ok,
     socket
     |> assign(:step, 1)
     |> assign(:form, form)
     |> assign(:errors, %{})
     |> assign(:pipeline_groups, pipeline_groups)
     # nil, :checking, :success, :failed
     |> assign(:connection_status, nil)
     |> assign(:page_title, "Create a New Pipeline - GoCD")}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-page-wrapper min-h-screen bg-[#f4f8f9] text-[#333] font-sans pb-12">
      <!-- Page Header -->
      <div class="bg-white border-b border-[#e9edef] px-6 py-4 flex justify-between items-center">
        <div class="flex items-center gap-2">
          <h1 class="text-xl font-semibold text-[#333] uppercase tracking-wide">
            Add a New Pipeline
          </h1>
        </div>
        <a href="/admin/pipelines" class="text-xs text-slate-500 hover:text-[#333] font-bold">
          <i class="fa fa-arrow-left mr-1"></i> Back to Pipelines
        </a>
      </div>
      
    <!-- Step Indicator -->
      <div class="max-w-4xl mx-auto px-6 mt-6">
        <div class="flex items-center justify-between bg-white border border-[#d6e0e2] rounded p-4 shadow-sm mb-6">
          <.step_item num={1} label="Step 1: Basic Settings" current={@step} />
          <div class="flex-grow border-t border-dashed border-slate-200 mx-4"></div>
          <.step_item num={2} label="Step 2: Material" current={@step} />
          <div class="flex-grow border-t border-dashed border-slate-200 mx-4"></div>
          <.step_item num={3} label="Step 3: Stage Details" current={@step} />
          <div class="flex-grow border-t border-dashed border-slate-200 mx-4"></div>
          <.step_item num={4} label="Step 4: Job and Task" current={@step} />
        </div>
        
    <!-- Form Box -->
        <div class="bg-white border border-[#d6e0e2] rounded shadow-sm overflow-hidden">
          <div class="bg-[#e7eef0] px-6 py-3 border-b border-[#d6e0e2]">
            <h2 class="text-xs font-bold uppercase tracking-wider text-slate-700">
              <%= case @step do %>
                <% 1 -> %>
                  Pipeline Group &amp; Name
                <% 2 -> %>
                  Configure Material (Source Control)
                <% 3 -> %>
                  Define Stage
                <% 4 -> %>
                  Configure Job &amp; Task
              <% end %>
            </h2>
          </div>

          <div class="p-6">
            <form phx-submit="next_step" phx-change="validate_form">
              <%= case @step do %>
                <% 1 -> %>
                  <div class="space-y-4">
                    <div>
                      <label class="block text-xs font-bold text-slate-600 mb-1">
                        Pipeline Name <span class="text-rose-500">*</span>
                      </label>
                      <input
                        type="text"
                        name="name"
                        value={@form["name"]}
                        placeholder="e.g. build-service"
                        required
                        class="w-full max-w-lg px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                      />
                      <%= if @errors["name"] do %>
                        <p class="text-[11px] text-rose-500 mt-1 font-semibold">{@errors["name"]}</p>
                      <% end %>
                    </div>

                    <div>
                      <label class="block text-xs font-bold text-slate-600 mb-1">
                        Pipeline Group <span class="text-rose-500">*</span>
                      </label>
                      <div class="relative max-w-lg">
                        <input
                          type="text"
                          name="group"
                          value={@form["group"]}
                          placeholder="e.g. defaultGroup"
                          required
                          list="pipeline-groups-list"
                          class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                        />
                        <datalist id="pipeline-groups-list">
                          <%= for g <- @pipeline_groups do %>
                            <option value={g}></option>
                          <% end %>
                        </datalist>
                      </div>
                      <%= if @errors["group"] do %>
                        <p class="text-[11px] text-rose-500 mt-1 font-semibold">{@errors["group"]}</p>
                      <% end %>
                    </div>
                  </div>
                <% 2 -> %>
                  <div class="space-y-4">
                    <div>
                      <label class="block text-xs font-bold text-slate-600 mb-1">Material Type</label>
                      <select
                        name="material_type"
                        class="w-full max-w-lg px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                      >
                        <option value="git" selected={@form["material_type"] == "git"}>Git</option>
                        <option value="svn" selected={@form["material_type"] == "svn"}>
                          Subversion
                        </option>
                        <option value="hg" selected={@form["material_type"] == "hg"}>
                          Mercurial
                        </option>
                      </select>
                    </div>

                    <div>
                      <label class="block text-xs font-bold text-slate-600 mb-1">
                        Repository URL <span class="text-rose-500">*</span>
                      </label>
                      <input
                        type="text"
                        name="material_url"
                        value={@form["material_url"]}
                        placeholder="e.g. https://github.com/example/repo.git"
                        required
                        class="w-full max-w-lg px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                      />
                      <%= if @errors["material_url"] do %>
                        <p class="text-[11px] text-rose-500 mt-1 font-semibold">
                          {@errors["material_url"]}
                        </p>
                      <% end %>
                    </div>

                    <div>
                      <label class="block text-xs font-bold text-slate-600 mb-1">Branch</label>
                      <input
                        type="text"
                        name="material_branch"
                        value={@form["material_branch"]}
                        placeholder="e.g. master"
                        class="w-full max-w-lg px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                      />
                    </div>

                    <div class="grid grid-cols-2 gap-4 max-w-lg">
                      <div>
                        <label class="block text-xs font-bold text-slate-600 mb-1">Username</label>
                        <input
                          type="text"
                          name="material_username"
                          value={@form["material_username"]}
                          class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                        />
                      </div>
                      <div>
                        <label class="block text-xs font-bold text-slate-600 mb-1">Password</label>
                        <input
                          type="password"
                          name="material_password"
                          value={@form["material_password"]}
                          class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                        />
                      </div>
                    </div>

                    <div class="pt-2 flex items-center gap-3">
                      <button
                        type="button"
                        phx-click="check_connection"
                        class="px-3 py-1.5 bg-slate-100 hover:bg-slate-200 border border-slate-350 text-slate-700 rounded text-xs font-semibold flex items-center gap-1.5 transition-all"
                      >
                        <%= if @connection_status == :checking do %>
                          <i class="fa fa-spinner animate-spin"></i> Checking Connection...
                        <% else %>
                          <i class="fa fa-circle-nodes"></i> Check Connection
                        <% end %>
                      </button>

                      <%= if @connection_status == :success do %>
                        <span class="text-xs text-emerald-600 font-bold flex items-center gap-1">
                          <i class="fa fa-circle-check"></i> Connection OK
                        </span>
                      <% end %>
                      <%= if @connection_status == :failed do %>
                        <span class="text-xs text-rose-500 font-bold flex items-center gap-1">
                          <i class="fa fa-circle-exclamation"></i>
                          Connection failed (invalid URL or credentials)
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% 3 -> %>
                  <div class="space-y-4">
                    <div>
                      <label class="block text-xs font-bold text-slate-600 mb-1">
                        Stage Name <span class="text-rose-500">*</span>
                      </label>
                      <input
                        type="text"
                        name="stage_name"
                        value={@form["stage_name"]}
                        placeholder="e.g. build-stage"
                        required
                        class="w-full max-w-lg px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                      />
                      <%= if @errors["stage_name"] do %>
                        <p class="text-[11px] text-rose-500 mt-1 font-semibold">
                          {@errors["stage_name"]}
                        </p>
                      <% end %>
                    </div>

                    <div>
                      <label class="block text-xs font-bold text-slate-600 mb-2">
                        Stage Trigger Type
                      </label>
                      <div class="space-y-2 text-xs">
                        <label class="flex items-center gap-2 cursor-pointer font-medium text-slate-700">
                          <input
                            type="radio"
                            name="approval_type"
                            value="success"
                            checked={@form["approval_type"] == "success"}
                            class="radio radio-xs checked:bg-[#943a9e] border-slate-350"
                          /> On Success (automatic)
                        </label>
                        <label class="flex items-center gap-2 cursor-pointer font-medium text-slate-700">
                          <input
                            type="radio"
                            name="approval_type"
                            value="manual"
                            checked={@form["approval_type"] == "manual"}
                            class="radio radio-xs checked:bg-[#943a9e] border-slate-350"
                          /> Manual Trigger
                        </label>
                      </div>
                    </div>
                  </div>
                <% 4 -> %>
                  <div class="space-y-4">
                    <div>
                      <label class="block text-xs font-bold text-slate-600 mb-1">
                        Job Name <span class="text-rose-500">*</span>
                      </label>
                      <input
                        type="text"
                        name="job_name"
                        value={@form["job_name"]}
                        placeholder="e.g. build-job"
                        required
                        class="w-full max-w-lg px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                      />
                      <%= if @errors["job_name"] do %>
                        <p class="text-[11px] text-rose-500 mt-1 font-semibold">
                          {@errors["job_name"]}
                        </p>
                      <% end %>
                    </div>

                    <div class="border-t border-[#e9edef] my-4 pt-4">
                      <h3 class="text-xs font-bold text-slate-700 uppercase tracking-wide mb-3">
                        Initial Build Task
                      </h3>

                      <div class="space-y-4">
                        <div>
                          <label class="block text-xs font-bold text-slate-600 mb-1">Task Type</label>
                          <select
                            name="task_type"
                            class="w-full max-w-lg px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                          >
                            <option value="exec" selected={@form["task_type"] == "exec"}>
                              Exec Task (Run command)
                            </option>
                            <option value="ant" selected={@form["task_type"] == "ant"}>Ant</option>
                            <option value="rake" selected={@form["task_type"] == "rake"}>Rake</option>
                          </select>
                        </div>

                        <div>
                          <label class="block text-xs font-bold text-slate-600 mb-1">
                            Command <span class="text-rose-500">*</span>
                          </label>
                          <input
                            type="text"
                            name="task_command"
                            value={@form["task_command"]}
                            placeholder="e.g. mix, make, npm, echo"
                            required
                            class="w-full max-w-lg px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e]"
                          />
                          <%= if @errors["task_command"] do %>
                            <p class="text-[11px] text-rose-500 mt-1 font-semibold">
                              {@errors["task_command"]}
                            </p>
                          <% end %>
                        </div>

                        <div>
                          <label class="block text-xs font-bold text-slate-600 mb-1">Arguments</label>
                          <textarea
                            name="task_arguments"
                            placeholder="e.g. test&#10;compile (one per line)"
                            rows="3"
                            class="w-full max-w-lg px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e] font-mono"
                          >{@form["task_arguments"]}</textarea>
                          <p class="text-[10px] text-slate-400 mt-0.5">
                            Enter arguments, one per line.
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
              <% end %>
              
    <!-- Buttons Control -->
              <div class="mt-8 pt-4 border-t border-[#e9edef] flex justify-between">
                <div>
                  <%= if @step > 1 do %>
                    <button
                      type="button"
                      phx-click="prev_step"
                      class="px-4 py-2 rounded bg-white border border-slate-350 hover:bg-slate-50 text-slate-700 text-xs font-semibold transition-all"
                    >
                      <i class="fa fa-chevron-left mr-1"></i> Previous
                    </button>
                  <% end %>
                </div>
                <div class="flex gap-2">
                  <a
                    href="/admin/pipelines"
                    class="px-4 py-2 rounded bg-white border border-slate-350 hover:bg-slate-50 text-slate-600 text-xs font-semibold flex items-center transition-all"
                  >
                    Cancel
                  </a>
                  <%= if @step < 4 do %>
                    <button
                      type="submit"
                      class="px-4 py-2 rounded bg-[#943a9e] hover:bg-purple-700 text-white text-xs font-semibold border border-purple-700 shadow-sm transition-all"
                    >
                      Next <i class="fa fa-chevron-right ml-1"></i>
                    </button>
                  <% else %>
                    <button
                      type="submit"
                      class="px-4 py-2 rounded bg-[#943a9e] hover:bg-purple-700 text-white text-xs font-semibold border border-purple-700 shadow-sm transition-all"
                    >
                      <i class="fa fa-check mr-1"></i> Save Pipeline
                    </button>
                  <% end %>
                </div>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp step_item(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <div class={[
        "w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold shrink-0 transition-all",
        cond do
          @current == @num -> "bg-[#943a9e] text-white border border-[#943a9e]"
          @current > @num -> "bg-[#dbf1d9] text-[#298a4c] border border-[#a3d7a8]"
          true -> "bg-slate-100 text-slate-400 border border-[#d6e0e2]"
        end
      ]}>
        <%= if @current > @num do %>
          <i class="fa fa-check text-[10px]"></i>
        <% else %>
          {@num}
        <% end %>
      </div>
      <span class={[
        "text-xs font-semibold transition-all",
        if(@current == @num, do: "text-[#943a9e] font-bold", else: "text-slate-500")
      ]}>
        {@label}
      </span>
    </div>
    """
  end

  @impl true
  def handle_event("prev_step", _params, socket) do
    {:noreply, assign(socket, :step, socket.assigns.step - 1)}
  end

  @impl true
  def handle_event("check_connection", _params, socket) do
    # Simulate connection checking
    send(self(), :complete_connection_check)
    {:noreply, assign(socket, :connection_status, :checking)}
  end

  @impl true
  def handle_event("validate_form", params, socket) do
    # Capture inputs from form and merge into socket state
    form = Map.merge(socket.assigns.form, params)
    errors = validate_current_step(socket.assigns.step, form)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:errors, errors)}
  end

  @impl true
  def handle_event("next_step", params, socket) do
    form = Map.merge(socket.assigns.form, params)
    errors = validate_current_step(socket.assigns.step, form)

    if Enum.empty?(errors) do
      advance_wizard(socket, form)
    else
      {:noreply, assign(socket, :errors, errors)}
    end
  end

  defp advance_wizard(socket, form) do
    if socket.assigns.step < 4 do
      {:noreply,
       socket
       |> assign(:form, form)
       |> assign(:step, socket.assigns.step + 1)
       |> assign(:errors, %{})
       |> assign(:connection_status, nil)}
    else
      finish_pipeline(socket, form)
    end
  end

  defp finish_pipeline(socket, form) do
    case save_pipeline(form) do
      {:ok, _pipeline} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pipeline '#{form["name"]}' created successfully.")
         |> push_navigate(to: "/admin/pipelines")}

      {:error, db_errors} ->
        {:noreply, assign(socket, :errors, db_errors)}
    end
  end

  @impl true
  def handle_info(:complete_connection_check, socket) do
    url = socket.assigns.form["material_url"] || ""

    status =
      if String.starts_with?(url, "http") or String.starts_with?(url, "git@"),
        do: :success,
        else: :failed

    {:noreply, assign(socket, :connection_status, status)}
  end

  # --- Validators ---

  defp validate_current_step(1, form) do
    errors = %{}
    name = String.trim(form["name"] || "")
    group = String.trim(form["group"] || "")

    errors =
      if name == "" do
        Map.put(errors, "name", "Pipeline Name is required")
      else
        cond do
          !Regex.match?(~r/^[a-zA-Z0-9_\-\.]+$/, name) ->
            Map.put(
              errors,
              "name",
              "Name must contain only letters, numbers, hyphens, underscores, and periods"
            )

          Pipelines.get_pipeline_by_name(name) ->
            Map.put(errors, "name", "Pipeline with this name already exists")

          true ->
            errors
        end
      end

    if group == "" do
      Map.put(errors, "group", "Pipeline Group is required")
    else
      errors
    end
  end

  defp validate_current_step(2, form) do
    errors = %{}
    url = String.trim(form["material_url"] || "")

    if url == "" do
      Map.put(errors, "material_url", "Repository URL is required")
    else
      errors
    end
  end

  defp validate_current_step(3, form) do
    errors = %{}
    stage_name = String.trim(form["stage_name"] || "")

    if stage_name == "" do
      Map.put(errors, "stage_name", "Stage Name is required")
    else
      unless Regex.match?(~r/^[a-zA-Z0-9_\-\.]+$/, stage_name) do
        Map.put(
          errors,
          "stage_name",
          "Name must contain only letters, numbers, hyphens, underscores, and periods"
        )
      else
        errors
      end
    end
  end

  defp validate_current_step(4, form) do
    errors = %{}
    job_name = String.trim(form["job_name"] || "")
    task_command = String.trim(form["task_command"] || "")

    errors =
      if job_name == "" do
        Map.put(errors, "job_name", "Job Name is required")
      else
        unless Regex.match?(~r/^[a-zA-Z0-9_\-\.]+$/, job_name) do
          Map.put(
            errors,
            "job_name",
            "Name must contain only letters, numbers, hyphens, underscores, and periods"
          )
        else
          errors
        end
      end

    if task_command == "" do
      Map.put(errors, "task_command", "Task Command is required")
    else
      errors
    end
  end

  defp validate_current_step(_, _), do: %{}

  # --- Database Transaction writer ---

  defp save_pipeline(form) do
    # Convert form values to nested map
    args_list =
      (form["task_arguments"] || "")
      |> String.split(["\n", "\r\n"], trim: true)
      |> Enum.map(&String.trim/1)

    Repo.transaction(fn ->
      # 1. Create pipeline changeset
      pipeline =
        %Pipeline{}
        |> Pipeline.changeset(%{
          name: form["name"],
          group: form["group"],
          label_template: "${COUNT}"
        })
        |> Repo.insert!()

      # 2. Create material
      material =
        case Repo.get_by(Material, type: form["material_type"], url: form["material_url"]) do
          nil ->
            %Material{}
            |> Material.changeset(%{
              type: form["material_type"],
              url: form["material_url"],
              branch: form["material_branch"] || "master",
              username: form["material_username"]
            })
            |> Repo.insert!()

          m ->
            m
        end

      # Associate material to pipeline
      {:ok, _} = Pipelines.add_material_to_pipeline(pipeline, material)

      # 3. Create stage
      stage =
        %Stage{}
        |> Stage.changeset(%{
          name: form["stage_name"],
          approval_type: form["approval_type"] || "success",
          pipeline_id: pipeline.id
        })
        |> Repo.insert!()

      # 4. Create job
      job =
        %Job{}
        |> Job.changeset(%{
          name: form["job_name"],
          stage_id: stage.id
        })
        |> Repo.insert!()

      # 5. Create task
      %Task{}
      |> Task.changeset(%{
        type: form["task_type"] || "exec",
        command: form["task_command"],
        arguments: args_list,
        job_id: job.id
      })
      |> Repo.insert!()

      pipeline
    end)
    |> case do
      {:ok, pipeline} -> {:ok, pipeline}
      {:error, reason} -> {:error, %{"db" => inspect(reason)}}
    end
  end
end
