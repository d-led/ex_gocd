defmodule ExGoCDWeb.ExternalCIRepoWizardLive do
  @moduledoc """
  Multi-step wizard for adding an external CI config repository.

  Steps:
    1. Repo details (URL, branch, source type, plugin)
    2. File discovery (simulated — shows expected workflow files)
    3. Per-file configuration (mode, jobs, triggers, overrides)
    4. Review & save
  """
  use ExGoCDWeb, :live_view

  import Ecto.Query

  alias ExGoCD.Repo
  alias ExGoCD.ConfigRepos.{ConfigRepo, ConfigRepoFile}

  @valid_modes ["translate", "execute_act", "execute_gitlab", "skip"]

  # ── Mount ──────────────────────────────────────────────────────────────────

  @impl true
  def mount(params, _session, socket) do
    socket =
      case params["id"] do
        nil -> mount_new(socket)
        id -> mount_edit(socket, id)
      end

    {:ok, socket}
  end

  defp mount_new(socket) do
    socket
    |> assign(:step, 1)
    |> assign(:editing, false)
    |> assign(:source_type, "github_actions")
    |> assign(:repo_url, "")
    |> assign(:branch, "main")
    |> assign(:plugin_id, "")
    |> assign(:configuration, %{})
    |> assign(:errors, %{})
    |> assign(:discovered_files, [])
    |> assign(:selected_paths, [])
    |> assign(:file_configs, %{})
    |> assign(:config_repo, nil)
    |> assign(:saved, false)
    |> assign(:saving, false)
  end

  defp mount_edit(socket, id) do
    case Repo.get(ConfigRepo, id) |> Repo.preload(:config_repo_files) do
      nil ->
        socket
        |> put_flash(:error, "Config repository not found.")
        |> redirect(to: "/admin/config_repos")

      config_repo ->
        existing_files = config_repo.config_repo_files || []

        socket
        |> assign(:step, 1)
        |> assign(:editing, true)
        |> assign(:source_type, config_repo.source_type || "github_actions")
        |> assign(:repo_url, config_repo.url || "")
        |> assign(:branch, config_repo.branch || "main")
        |> assign(:plugin_id, config_repo.plugin_id || "")
        |> assign(:configuration, config_repo.configuration || %{})
        |> assign(:errors, %{})
        |> assign(:discovered_files, simulate_discovery(config_repo.source_type))
        |> assign(:selected_paths, Enum.map(existing_files, & &1.path))
        |> assign(:file_configs, build_file_configs_from_repo(existing_files))
        |> assign(:config_repo, config_repo)
        |> assign(:saved, false)
        |> assign(:saving, false)
    end
  end

  defp build_file_configs_from_repo(existing_files) do
    Map.new(existing_files, fn f ->
      selection = Repo.get_by(ExGoCD.ConfigRepos.ConfigRepoFileSelection,
        config_repo_file_id: f.id)
      {f.path,
       %{
         mode: (selection && selection.mode) || "translate",
         selected_jobs: (selection && selection.selected_jobs) || [],
         selected_triggers: (selection && selection.selected_triggers) || [],
         overrides: (selection && selection.overrides) || %{}
       }}
    end)
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("set_source_type", %{"source_type" => st}, socket) do
    {:noreply, assign(socket, :source_type, st)}
  end

  def handle_event("step1_next", %{"repo_url" => url, "branch" => branch}, socket) do
    url = String.trim(url)
    branch = String.trim(branch)
    errors = validate_step1(url, branch)

    if errors != %{} do
      {:noreply, assign(socket, :errors, errors)}
    else
      do_step1_persist(socket, url, branch)
    end
  end

  def handle_event("step2_all", _params, socket) do
    all_paths = Enum.map(socket.assigns.discovered_files, & &1.path)
    advance_to_step3(socket, all_paths)
  end

  def handle_event("step2_none", _params, socket) do
    advance_to_step3(socket, [])
  end

  def handle_event("step2_toggle", %{"path" => path}, socket) do
    discovered = socket.assigns.discovered_files
    # Toggle selection in a temporary assign
    current_selected = socket.assigns[:selected_paths] || Enum.map(discovered, & &1.path)
    updated =
      if path in current_selected do
        current_selected -- [path]
      else
        current_selected ++ [path]
      end
    {:noreply, assign(socket, :selected_paths, updated)}
  end

  def handle_event("set_file_mode", %{"path" => path, "mode" => mode}, socket)
      when mode in @valid_modes do
    file_configs =
      Map.update!(socket.assigns.file_configs, path, fn cfg ->
        Map.put(cfg, :mode, mode)
      end)

    {:noreply, assign(socket, :file_configs, file_configs)}
  end

  def handle_event("toggle_file_job", %{"path" => path, "job" => job}, socket) do
    file_configs =
      Map.update!(socket.assigns.file_configs, path, fn cfg ->
        jobs = cfg.selected_jobs
        updated = if job in jobs, do: jobs -- [job], else: jobs ++ [job]
        Map.put(cfg, :selected_jobs, updated)
      end)

    {:noreply, assign(socket, :file_configs, file_configs)}
  end

  def handle_event("step3_next", _params, socket) do
    {:noreply, assign(socket, :step, 4)}
  end

  def handle_event("save_all", _params, socket) do
    {:noreply, assign(socket, :saving, true)}

    config_repo = socket.assigns.config_repo
    file_configs = socket.assigns.file_configs

    # If editing, delete old ConfigRepoFile records and their selections
    if socket.assigns.editing do
      old_files = Repo.all(from(f in ConfigRepoFile, where: f.config_repo_id == ^config_repo.id))
      Enum.each(old_files, fn f ->
        Repo.delete_all(from(s in ExGoCD.ConfigRepos.ConfigRepoFileSelection,
          where: s.config_repo_file_id == ^f.id))
      end)
      Repo.delete_all(from(f in ConfigRepoFile, where: f.config_repo_id == ^config_repo.id))
    end

    # Persist ConfigRepoFile + ConfigRepoFileSelection records
    Enum.each(file_configs, fn {path, cfg} ->
      {:ok, file} =
        %ConfigRepoFile{}
        |> ConfigRepoFile.changeset(%{
          config_repo_id: config_repo.id,
          path: path,
          source_type: config_repo.source_type,
          status: "new",
          checksum: "0000000000000000000000000000000000000000000000000000000000000000",
          raw_content: ""
        })
        |> Repo.insert()

      # Create selection record
      ExGoCD.ConfigRepos.ConfigRepoFileSelection.changeset(
        %ExGoCD.ConfigRepos.ConfigRepoFileSelection{},
        %{
          config_repo_file_id: file.id,
          mode: cfg.mode,
          selected_jobs: cfg.selected_jobs,
          selected_triggers: cfg.selected_triggers,
          overrides: cfg.overrides
        }
      )
      |> Repo.insert()
    end)

    {:noreply,
     socket
     |> assign(:saving, false)
     |> assign(:saved, true)}
  end

  def handle_event("prev_step", _params, socket) do
    step = max(socket.assigns.step - 1, 1)
    {:noreply, assign(socket, :step, step)}
  end

  def handle_event("jump_to", %{"step" => step_str}, socket) do
    step = String.to_integer(step_str)
    # Only allow jumping to completed or current steps
    max_step = socket.assigns.step
    target = min(step, max_step)
    {:noreply, assign(socket, :step, target)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, redirect(socket, to: "/admin/config_repos")}
  end

  def handle_event("step2_continue", _params, socket) do
    selected = socket.assigns[:selected_paths] || Enum.map(socket.assigns.discovered_files, & &1.path)
    advance_to_step3(socket, selected)
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp do_step1_persist(socket, url, branch) do
    if socket.assigns.editing do
      do_step1_update(socket, url, branch)
    else
      do_step1_create(socket, url, branch)
    end
  end

  defp do_step1_update(socket, url, branch) do
    changeset = ConfigRepo.changeset(socket.assigns.config_repo, %{
      url: url, branch: branch,
      source_type: socket.assigns.source_type,
      plugin_id: socket.assigns.plugin_id,
      configuration: socket.assigns.configuration
    })

    case Repo.update(changeset) do
      {:ok, config_repo} ->
        discovered = simulate_discovery(config_repo.source_type)
        existing_paths = config_repo
          |> Repo.preload(:config_repo_files)
          |> Map.get(:config_repo_files, [])
          |> Enum.map(& &1.path)
        all_paths = Enum.uniq(existing_paths ++ Enum.map(discovered, & &1.path))
        advance_from_step1(socket, url, branch, config_repo, discovered, all_paths)

      {:error, changeset} ->
        url_error = error_msg(changeset, "update")
        {:noreply, assign(socket, :errors, %{repo_url: url_error})}
    end
  end

  defp do_step1_create(socket, url, branch) do
    case %ConfigRepo{}
         |> ConfigRepo.changeset(%{
           url: url, branch: branch,
           source_type: socket.assigns.source_type,
           plugin_id: socket.assigns.plugin_id,
           configuration: socket.assigns.configuration,
           material_type: "git"
         })
         |> Repo.insert() do
      {:ok, config_repo} ->
        discovered = simulate_discovery(socket.assigns.source_type)
        paths = Enum.map(discovered, & &1.path)
        advance_from_step1(socket, url, branch, config_repo, discovered, paths)

      {:error, changeset} ->
        url_error = error_msg(changeset, "create")
        {:noreply, assign(socket, :errors, %{repo_url: url_error})}
    end
  end

  defp advance_from_step1(socket, url, branch, config_repo, discovered, paths) do
    {:noreply,
     socket
     |> assign(:repo_url, url)
     |> assign(:branch, branch)
     |> assign(:errors, %{})
     |> assign(:config_repo, config_repo)
     |> assign(:discovered_files, discovered)
     |> assign(:selected_paths, paths)
     |> assign(:step, 2)}
  end

  defp error_msg(changeset, _action) do
    if changeset.errors[:url],
      do: "URL already exists or is invalid",
      else: "Failed to save config repo"
  end

  defp advance_to_step3(socket, selected_paths) do
    file_configs =
      Map.new(selected_paths, fn path ->
        file = Enum.find(socket.assigns.discovered_files, &(&1.path == path))
        {path,
         %{
           mode: "translate",
           selected_jobs: (file && file.job_names) || [],
           selected_triggers: [],
           overrides: %{}
         }}
      end)

    {:noreply,
     socket
     |> assign(:file_configs, file_configs)
     |> assign(:step, 3)}
  end

  # ── Validation ─────────────────────────────────────────────────────────────

  defp validate_step1("", _branch), do: %{repo_url: "Repository URL is required"}
  defp validate_step1(_url, ""), do: %{branch: "Branch is required"}
  defp validate_step1(url, _branch) do
    unless String.starts_with?(url, "http") or String.starts_with?(url, "git@") do
      %{repo_url: "Must be a valid git URL (http/https/git@)"}
    else
      %{}
    end
  end

  # ── Simulated file discovery ───────────────────────────────────────────────

  defp simulate_discovery("github_actions") do
    [
      %{path: ".github/workflows/ci.yml", job_names: ["build", "test", "lint"]},
      %{path: ".github/workflows/deploy.yml", job_names: ["deploy-staging", "deploy-prod"]},
      %{path: ".github/workflows/nightly.yml", job_names: ["nightly-build"]}
    ]
  end

  defp simulate_discovery("gitlab_ci") do
    [
      %{path: ".gitlab-ci.yml", job_names: ["build", "test", "deploy"]}
    ]
  end

  defp simulate_discovery(_), do: []

  # ── Helpers ────────────────────────────────────────────────────────────────

  def source_type_label("github_actions"), do: "GitHub Actions"
  def source_type_label("gitlab_ci"), do: "GitLab CI"
  def source_type_label("gocd_pipeline"), do: "GoCD Pipeline Config"
  def source_type_label(_), do: "GoCD Pipeline Config"

  def mode_label("translate"), do: "Translate to GoCD"
  def mode_label("execute_act"), do: "Execute via act"
  def mode_label("execute_gitlab"), do: "Execute via gitlab-runner"
  def mode_label("skip"), do: "Skip"

  # ── Render ─────────────────────────────────────────────────────────────────

  @step_labels ["Repository", "Files", "Configure", "Review"]

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :step_labels, @step_labels)

    ~H"""
    <div class="min-h-screen bg-[#f2f2f2]">
      <%= if @saved do %>
        <div class="max-w-lg mx-auto pt-16 px-4">
          <div class="bg-white rounded border border-[#d6e0e2] p-8 text-center shadow-sm">
            <div class="text-5xl mb-4">✅</div>
            <h2 class="text-lg font-bold text-slate-700 mb-2">Repository added</h2>
            <p class="text-sm text-slate-500 mb-2">
              {@config_repo.url}
            </p>
            <p class="text-xs text-slate-400 mb-6">
              {map_size(@file_configs)} workflow file(s) configured. They will appear in the config repos list.
            </p>
            <a href="/admin/config_repos" class="inline-block px-4 py-2 rounded bg-[#943a9e] hover:bg-purple-700 text-xs font-bold text-white shadow-sm transition-all">
              ← Back to Config Repos
            </a>
          </div>
        </div>
      <% else %>
        <div class="max-w-3xl mx-auto pt-6 px-4">
          <%!-- Header with cancel --%>
          <div class="flex items-center justify-between mb-4">
            <h1 class="text-sm font-bold text-slate-700">{if @editing, do: "Re-sync Config Repository", else: "Add Config Repository"}</h1>
            <button phx-click="cancel" class="text-xs text-slate-400 hover:text-red-500 transition-colors">
              Cancel
            </button>
          </div>

          <%!-- Labeled progress indicator — clickable for completed steps --%>
          <div class="flex items-center gap-1 mb-8">
            <%= for {label, i} <- Enum.with_index(@step_labels, 1) do %>
              <button
                phx-click="jump_to"
                phx-value-step={i}
                disabled={i > @step}
                class={[
                  "flex-1 text-center py-1.5 rounded text-[10px] font-bold transition-all",
                  if(i < @step, do: "bg-emerald-100 text-emerald-700 cursor-pointer hover:bg-emerald-200"),
                  if(i == @step, do: "bg-[#943a9e] text-white"),
                  if(i > @step, do: "bg-slate-100 text-slate-400 cursor-not-allowed")
                ]}
              >
                {i}. {label}
              </button>
              <%= if i < 4 do %>
                <div class={["w-4 h-0.5", if(i < @step, do: "bg-emerald-300", else: "bg-slate-200")]}></div>
              <% end %>
            <% end %>
          </div>

          <%!-- Step content --%>
          <%= case @step do %>
            <% 1 -> %>
              <.step1_form
                source_type={@source_type}
                repo_url={@repo_url}
                branch={@branch}
                errors={@errors}
              />
            <% 2 -> %>
              <.step2_files
                source_type={@source_type}
                discovered_files={@discovered_files}
                selected_paths={@selected_paths}
                repo_url={@repo_url}
              />
            <% 3 -> %>
              <.step3_config
                source_type={@source_type}
                file_configs={@file_configs}
                discovered_files={@discovered_files}
              />
            <% 4 -> %>
              <.step4_review
                config_repo={@config_repo}
                file_configs={@file_configs}
                saving={@saving}
              />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Step 1: Repo details ───────────────────────────────────────────────────

  defp step1_form(assigns) do
    ~H"""
    <div class="bg-white rounded border border-[#d6e0e2] p-6 shadow-sm">
      <h2 class="text-base font-bold text-slate-700 mb-1">Where is your pipeline?</h2>
      <p class="text-xs text-slate-400 mb-6">Paste the URL of a GitHub or GitLab repository that contains workflow files.</p>

      <form phx-submit="step1_next" class="space-y-5">
        <%!-- Source type — integrated into the form --%>
        <div>
          <label class="block text-[11px] font-bold uppercase text-slate-500 mb-2">Source</label>
          <div class="flex gap-2">
            <label class={[
              "flex items-center gap-2 px-4 py-2.5 rounded border cursor-pointer text-xs font-bold transition-all",
              if(@source_type == "github_actions",
                do: "bg-purple-50 text-purple-700 border-purple-400 ring-1 ring-purple-300",
                else: "bg-white text-slate-500 border-[#d6e0e2] hover:border-purple-300"
              )
            ]}>
              <input type="radio" name="source_type" value="github_actions" checked={@source_type == "github_actions"} phx-click="set_source_type" phx-value-source_type="github_actions" class="sr-only" />
              <span class="text-base"></span> GitHub Actions
            </label>
            <label class={[
              "flex items-center gap-2 px-4 py-2.5 rounded border cursor-pointer text-xs font-bold transition-all",
              if(@source_type == "gitlab_ci",
                do: "bg-orange-50 text-orange-700 border-orange-400 ring-1 ring-orange-300",
                else: "bg-white text-slate-500 border-[#d6e0e2] hover:border-orange-300"
              )
            ]}>
              <input type="radio" name="source_type" value="gitlab_ci" checked={@source_type == "gitlab_ci"} phx-click="set_source_type" phx-value-source_type="gitlab_ci" class="sr-only" />
              <span class="text-base"></span> GitLab CI
            </label>
            <label class={[
              "flex items-center gap-2 px-4 py-2.5 rounded border cursor-pointer text-xs font-bold transition-all",
              if(@source_type == "gocd_pipeline",
                do: "bg-emerald-50 text-emerald-700 border-emerald-400 ring-1 ring-emerald-300",
                else: "bg-white text-slate-500 border-[#d6e0e2] hover:border-emerald-300"
              )
            ]}>
              <input type="radio" name="source_type" value="gocd_pipeline" checked={@source_type == "gocd_pipeline"} phx-click="set_source_type" phx-value-source_type="gocd_pipeline" class="sr-only" />
              <span class="text-base">⚙</span> GoCD Pipeline Config
            </label>
          </div>
        </div>

        <%!-- Repo URL with examples --%>
        <div>
          <label class="block text-[11px] font-bold uppercase text-slate-500 mb-1.5" for="repo_url">Repository URL</label>
          <input
            type="text"
            id="repo_url"
            name="repo_url"
            value={@repo_url}
            placeholder="https://github.com/org/repo.git"
            autocomplete="url"
            class={[
              "w-full border rounded px-3 py-2.5 text-sm outline-none transition-all",
              if(@errors[:repo_url], do: "border-red-300 focus:border-red-400", else: "border-[#d6e0e2] focus:border-[#943a9e]")
            ]}
          />
          <p class="text-[10px] text-slate-400 mt-1">Example: https://github.com/myteam/backend.git</p>
          <%= if @errors[:repo_url] do %>
            <p class="text-red-500 text-xs mt-1 flex items-center gap-1">
              <span>⚠</span> {@errors[:repo_url]}
            </p>
          <% end %>
        </div>

        <%!-- Branch --%>
        <div>
          <label class="block text-[11px] font-bold uppercase text-slate-500 mb-1.5" for="branch">Branch</label>
          <input
            type="text"
            id="branch"
            name="branch"
            value={@branch}
            placeholder="main"
            class={[
              "w-full border rounded px-3 py-2.5 text-sm outline-none transition-all",
              if(@errors[:branch], do: "border-red-300 focus:border-red-400", else: "border-[#d6e0e2] focus:border-[#943a9e]")
            ]}
          />
          <%= if @errors[:branch] do %>
            <p class="text-red-500 text-xs mt-1 flex items-center gap-1">
              <span>⚠</span> {@errors[:branch]}
            </p>
          <% end %>
        </div>

        <button
          type="submit"
          class="mt-4 w-full py-2.5 rounded bg-[#943a9e] hover:bg-purple-700 text-xs font-bold text-white shadow-sm transition-all flex items-center justify-center gap-2"
        >
          Find workflow files →
        </button>
      </form>
    </div>
    """
  end

  # ── Step 2: File discovery ─────────────────────────────────────────────────

  defp step2_files(assigns) do
    ~H"""
    <div class="bg-white rounded border border-[#d6e0e2] p-6 shadow-sm">
      <h2 class="text-base font-bold text-slate-700 mb-1">Files found in this repository</h2>
      <p class="text-xs text-slate-400 mb-4">
        We found {length(@discovered_files)} workflow {ngettext("file", "files", length(@discovered_files))}.
        Uncheck any you don't want to import.
      </p>

      <%= if Enum.empty?(@discovered_files) do %>
        <div class="text-center py-12 text-slate-400">
          <p class="text-sm mb-2">No workflow files found</p>
          <button phx-click="prev_step" class="text-xs text-[#943a9e] hover:underline">← Try a different repository</button>
        </div>
      <% else %>
        <%!-- Select / deselect all --%>
        <div class="flex items-center gap-2 mb-3">
          <button phx-click="step2_all" class="text-[10px] text-[#943a9e] hover:underline font-medium">Select all</button>
          <span class="text-slate-300">·</span>
          <button phx-click="step2_none" class="text-[10px] text-[#943a9e] hover:underline font-medium">Deselect all</button>
        </div>

        <div class="space-y-1 mb-6">
          <%= for file <- @discovered_files do %>
            <% checked = file.path in @selected_paths %>
            <label
              phx-click="step2_toggle"
              phx-value-path={file.path}
              class={[
                "flex items-center gap-3 p-3 rounded border cursor-pointer transition-all",
                if(checked, do: "border-[#943a9e] bg-purple-50/30", else: "border-[#d6e0e2] hover:bg-slate-50")
              ]}
            >
              <input type="checkbox" checked={checked} class="rounded pointer-events-none" />
              <div class="flex-1 min-w-0">
                <span class="text-sm font-mono text-slate-700 truncate block">{file.path}</span>
              </div>
              <div class="flex items-center gap-2 flex-shrink-0">
                <span class="text-[10px] text-slate-400 tabular-nums">
                  {length(file.job_names)} {ngettext("job", "jobs", length(file.job_names))}
                </span>
                <span class={[
                  "px-1.5 py-0.5 rounded text-[9px] font-bold",
                  if(@source_type == "github_actions", do: "bg-purple-100 text-purple-700", else: "bg-orange-100 text-orange-700")
                ]}>
                  {source_type_label(@source_type)}
                </span>
              </div>
            </label>
          <% end %>
        </div>

        <div class="flex gap-3">
          <button
            type="button"
            phx-click="prev_step"
            class="px-4 py-2 rounded border border-[#d6e0e2] text-xs font-bold text-slate-500 hover:bg-slate-50 transition-all"
          >
            ← Back
          </button>
          <button
            type="button"
            phx-click="step2_continue"
            disabled={Enum.empty?(@selected_paths)}
            class={[
              "flex-1 py-2.5 rounded text-xs font-bold text-white shadow-sm transition-all flex items-center justify-center gap-2",
              if(Enum.empty?(@selected_paths), do: "bg-slate-300 cursor-not-allowed", else: "bg-[#943a9e] hover:bg-purple-700")
            ]}
          >
            Configure {length(@selected_paths)} {ngettext("file", "files", length(@selected_paths))} →
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Step 3: Per-file configuration ─────────────────────────────────────────

  defp step3_config(assigns) do
    assigns = assign(assigns, :valid_modes, ["translate", "execute_act", "execute_gitlab", "skip"])

    ~H"""
    <div class="bg-white rounded border border-[#d6e0e2] p-6 shadow-sm">
      <h2 class="text-base font-bold text-slate-700 mb-6 flex items-center gap-2">
        <span class="w-7 h-7 rounded-full bg-[#943a9e] text-white text-xs flex items-center justify-center font-bold">3</span>
        Configure Files
      </h2>

      <div class="space-y-6">
        <%= for {path, cfg} <- @file_configs do %>
          <% file = Enum.find(@discovered_files, &(&1.path == path)) %>
          <div class="border border-[#d6e0e2] rounded p-4">
            <h3 class="text-sm font-bold text-slate-700 mb-3 font-mono">{path}</h3>

            <%!-- Mode selector --%>
            <div class="mb-3">
              <label class="block text-[10px] font-bold uppercase text-slate-400 mb-1.5">Mode</label>
              <div class="flex flex-wrap gap-1.5">
                <%= for mode <- @valid_modes do %>
                  <button
                    type="button"
                    phx-click="set_file_mode"
                    phx-value-path={path}
                    phx-value-mode={mode}
                    class={[
                      "px-3 py-1.5 rounded text-[10px] font-bold border transition-all",
                      if(cfg.mode == mode,
                        do: "bg-[#943a9e] text-white border-[#943a9e]",
                        else: "bg-white text-slate-500 border-[#d6e0e2] hover:border-[#943a9e]"
                      )
                    ]}
                  >
                    {mode_label(mode)}
                  </button>
                <% end %>
              </div>
            </div>

            <%!-- Job selection (only when mode is translate or execute) --%>
            <%= if cfg.mode in ["translate", "execute_act", "execute_gitlab"] and not is_nil(file) do %>
              <div>
                <label class="block text-[10px] font-bold uppercase text-slate-400 mb-1.5">
                  Jobs ({length(cfg.selected_jobs)}/{length(file.job_names)} selected)
                </label>
                <div class="flex flex-wrap gap-1.5">
                  <%= for job <- file.job_names do %>
                    <button
                      type="button"
                      phx-click="toggle_file_job"
                      phx-value-path={path}
                      phx-value-job={job}
                      class={[
                        "px-2.5 py-1 rounded text-[10px] font-bold border transition-all",
                        if(job in cfg.selected_jobs,
                          do: "bg-emerald-50 text-emerald-700 border-emerald-300",
                          else: "bg-white text-slate-400 border-[#d6e0e2] hover:border-emerald-300"
                        )
                      ]}
                    >
                      {job}
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="flex gap-3 mt-6">
        <button
          type="button"
          phx-click="prev_step"
          class="px-4 py-2 rounded border border-[#d6e0e2] text-xs font-bold text-slate-500 hover:bg-slate-50 transition-all"
        >
          <i class="fa fa-arrow-left mr-1"></i> Back
        </button>
        <button
          phx-click="step3_next"
          class="flex-1 py-2.5 rounded bg-[#943a9e] hover:bg-purple-700 text-xs font-bold text-white shadow-sm transition-all"
        >
          Next: Review <i class="fa fa-arrow-right ml-1"></i>
        </button>
      </div>
    </div>
    """
  end

  # ── Step 4: Review & Save ──────────────────────────────────────────────────

  defp step4_review(assigns) do
    ~H"""
    <div class="bg-white rounded border border-[#d6e0e2] p-6 shadow-sm">
      <h2 class="text-base font-bold text-slate-700 mb-6 flex items-center gap-2">
        <span class="w-7 h-7 rounded-full bg-[#943a9e] text-white text-xs flex items-center justify-center font-bold">4</span>
        Review &amp; Save
      </h2>

      <%!-- Summary --%>
      <div class="bg-slate-50 rounded border border-[#d6e0e2] p-4 mb-6 space-y-2 text-sm">
        <div class="flex justify-between">
          <span class="text-slate-500">Repository:</span>
          <span class="font-bold text-slate-700 font-mono text-xs">{@config_repo.url}</span>
        </div>
        <div class="flex justify-between">
          <span class="text-slate-500">Branch:</span>
          <span class="font-bold text-slate-700">{@config_repo.branch}</span>
        </div>
        <div class="flex justify-between">
          <span class="text-slate-500">Source Type:</span>
          <span class="font-bold text-slate-700">{source_type_label(@config_repo.source_type)}</span>
        </div>
        <div class="flex justify-between">
          <span class="text-slate-500">Files:</span>
          <span class="font-bold text-slate-700">{length(Map.keys(@file_configs))}</span>
        </div>
      </div>

      <%!-- Per-file summary --%>
      <div class="space-y-3 mb-6">
        <h3 class="text-xs font-bold uppercase text-slate-400">File Configuration</h3>
        <%= for {path, cfg} <- @file_configs do %>
          <div class="border border-[#d6e0e2] rounded p-3 flex items-center justify-between">
            <div>
              <span class="text-sm font-mono text-slate-700">{path}</span>
              <span class="ml-2 text-[10px] text-slate-400">
                {length(cfg.selected_jobs)} jobs
              </span>
            </div>
            <span class={[
              "px-2 py-0.5 rounded text-[10px] font-bold",
              case cfg.mode do
                "translate" -> "bg-emerald-50 text-emerald-700"
                "execute_act" -> "bg-blue-50 text-blue-700"
                "execute_gitlab" -> "bg-orange-50 text-orange-700"
                _ -> "bg-slate-100 text-slate-500"
              end
            ]}>
              {mode_label(cfg.mode)}
            </span>
          </div>
        <% end %>
      </div>

      <div class="flex gap-3">
        <button
          type="button"
          phx-click="prev_step"
          class="px-4 py-2 rounded border border-[#d6e0e2] text-xs font-bold text-slate-500 hover:bg-slate-50 transition-all"
        >
          <i class="fa fa-arrow-left mr-1"></i> Back
        </button>
        <button
          phx-click="save_all"
          disabled={@saving}
          class="flex-1 py-2.5 rounded bg-emerald-600 hover:bg-emerald-700 disabled:bg-slate-200 text-xs font-bold text-white shadow-sm transition-all flex items-center justify-center gap-2"
        >
          <%= if @saving do %>
            <i class="fa fa-spinner animate-spin"></i> Saving...
          <% else %>
            <i class="fa fa-check"></i> Save &amp; Finish
          <% end %>
        </button>
      </div>
    </div>
    """
  end
end
