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

  alias ExGoCD.Repo
  alias ExGoCD.ConfigRepos.{ConfigRepo, ConfigRepoFile}

  @valid_modes ["translate", "execute_act", "execute_gitlab", "skip"]

  # ── Mount ──────────────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:step, 1)
     |> assign(:source_type, "github_actions")
     |> assign(:repo_url, "")
     |> assign(:branch, "main")
     |> assign(:plugin_id, "")
     |> assign(:configuration, %{})
     |> assign(:errors, %{})
     |> assign(:discovered_files, [])
     |> assign(:file_configs, %{})
     |> assign(:config_repo, nil)
     |> assign(:saved, false)
     |> assign(:saving, false)}
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

    if errors == %{} do
      # Create the config repo immediately
      case %ConfigRepo{}
           |> ConfigRepo.changeset(%{
             url: url,
             branch: branch,
             source_type: socket.assigns.source_type,
             plugin_id: socket.assigns.plugin_id,
             configuration: socket.assigns.configuration,
             material_type: "git"
           })
           |> Repo.insert() do
        {:ok, config_repo} ->
          # Simulate file discovery based on source type
          discovered = simulate_discovery(socket.assigns.source_type)

          {:noreply,
           socket
           |> assign(:repo_url, url)
           |> assign(:branch, branch)
           |> assign(:errors, %{})
           |> assign(:config_repo, config_repo)
           |> assign(:discovered_files, discovered)
           |> assign(:step, 2)}

        {:error, changeset} ->
          url_error =
            if changeset.errors[:url],
              do: "URL already exists or is invalid",
              else: "Failed to create config repo"

          {:noreply, assign(socket, :errors, %{repo_url: url_error})}
      end
    else
      {:noreply, assign(socket, :errors, errors)}
    end
  end

  def handle_event("step2_next", %{"selected_files" => selected}, socket) do
    selected_paths = selected_paths_from_params(selected)
    advance_to_step3(socket, selected_paths)
  end

  # Fallback: no checkboxes submitted (all unchecked)
  def handle_event("step2_next", _params, socket) do
    advance_to_step3(socket, [])
  end

  defp selected_paths_from_params(selected) when is_list(selected), do: selected
  defp selected_paths_from_params(selected) when is_binary(selected), do: [selected]
  defp selected_paths_from_params(_), do: []

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
  def source_type_label(_), do: "GoCD Pipeline"

  def mode_label("translate"), do: "Translate to GoCD"
  def mode_label("execute_act"), do: "Execute via act"
  def mode_label("execute_gitlab"), do: "Execute via gitlab-runner"
  def mode_label("skip"), do: "Skip"

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f2f2f2]">
      <%= if @saved do %>
        <div class="max-w-2xl mx-auto pt-12 px-4">
          <div class="bg-white rounded border border-[#d6e0e2] p-8 text-center shadow-sm">
            <div class="text-5xl mb-4">✅</div>
            <h2 class="text-lg font-bold text-slate-700 mb-2">Config Repository Added</h2>
            <p class="text-sm text-slate-500 mb-6">
              {@config_repo.url} has been added with {map_size(@file_configs)} workflow files configured.
            </p>
            <a href="/admin/config_repos" class="inline-block px-4 py-2 rounded bg-[#943a9e] hover:bg-purple-700 text-xs font-bold text-white shadow-sm transition-all">
              Back to Config Repos
            </a>
          </div>
        </div>
      <% else %>
        <div class="max-w-3xl mx-auto pt-8 px-4">
          <%!-- Progress indicator --%>
          <div class="flex items-center gap-2 mb-8">
            <%= for i <- 1..4 do %>
              <div class={[
                "flex-1 h-2 rounded-full transition-all",
                if(i <= @step, do: "bg-[#943a9e]", else: "bg-slate-200")
              ]}>
              </div>
            <% end %>
          </div>

          <%!-- Step content --%>
          <%= case @step do %>
            <% 1 -> %>
              <.step1_form
                source_type={@source_type}
                repo_url={@repo_url}
                branch={@branch}
                plugin_id={@plugin_id}
                errors={@errors}
              />
            <% 2 -> %>
              <.step2_files
                source_type={@source_type}
                discovered_files={@discovered_files}
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
      <h2 class="text-base font-bold text-slate-700 mb-6 flex items-center gap-2">
        <span class="w-7 h-7 rounded-full bg-[#943a9e] text-white text-xs flex items-center justify-center font-bold">1</span>
        Repository Details
      </h2>

      <div class="space-y-5">
        <%!-- Source type selector --%>
        <div>
          <label class="block text-[11px] font-bold uppercase text-slate-500 mb-2">Source Type</label>
          <div class="flex gap-2">
            <button
              phx-click="set_source_type"
              phx-value-source_type="github_actions"
              class={[
                "px-4 py-2 rounded text-xs font-bold border transition-all",
                if(@source_type == "github_actions",
                  do: "bg-purple-50 text-purple-700 border-purple-300",
                  else: "bg-white text-slate-500 border-[#d6e0e2] hover:border-purple-300"
                )
              ]}
            >
              <i class="fab fa-github mr-1"></i> GitHub Actions
            </button>
            <button
              phx-click="set_source_type"
              phx-value-source_type="gitlab_ci"
              class={[
                "px-4 py-2 rounded text-xs font-bold border transition-all",
                if(@source_type == "gitlab_ci",
                  do: "bg-orange-50 text-orange-700 border-orange-300",
                  else: "bg-white text-slate-500 border-[#d6e0e2] hover:border-orange-300"
                )
              ]}
            >
              <i class="fab fa-gitlab mr-1"></i> GitLab CI
            </button>
          </div>
        </div>

        <%!-- Repo URL --%>
        <div>
          <label class="block text-[11px] font-bold uppercase text-slate-500 mb-2">Repository URL</label>
          <form phx-submit="step1_next">
            <input
              type="text"
              name="repo_url"
              value={@repo_url}
              placeholder="https://github.com/org/repo.git"
              class={[
                "w-full border rounded px-3 py-2 text-sm outline-none transition-all",
                if(@errors[:repo_url], do: "border-red-300 focus:border-red-400", else: "border-[#d6e0e2] focus:border-[#943a9e]")
              ]}
            />
            <%= if @errors[:repo_url] do %>
              <p class="text-red-500 text-xs mt-1">{@errors[:repo_url]}</p>
            <% end %>

            <%!-- Branch --%>
            <label class="block text-[11px] font-bold uppercase text-slate-500 mb-2 mt-4">Branch</label>
            <input
              type="text"
              name="branch"
              value={@branch}
              placeholder="main"
              class={[
                "w-full border rounded px-3 py-2 text-sm outline-none transition-all",
                if(@errors[:branch], do: "border-red-300 focus:border-red-400", else: "border-[#d6e0e2] focus:border-[#943a9e]")
              ]}
            />
            <%= if @errors[:branch] do %>
              <p class="text-red-500 text-xs mt-1">{@errors[:branch]}</p>
            <% end %>

            <button
              type="submit"
              class="mt-6 w-full py-2.5 rounded bg-[#943a9e] hover:bg-purple-700 text-xs font-bold text-white shadow-sm transition-all flex items-center justify-center gap-2"
            >
              Next: Discover Files <i class="fa fa-arrow-right"></i>
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # ── Step 2: File discovery ─────────────────────────────────────────────────

  defp step2_files(assigns) do
    ~H"""
    <div class="bg-white rounded border border-[#d6e0e2] p-6 shadow-sm">
      <h2 class="text-base font-bold text-slate-700 mb-2 flex items-center gap-2">
        <span class="w-7 h-7 rounded-full bg-[#943a9e] text-white text-xs flex items-center justify-center font-bold">2</span>
        Discovered Workflow Files
      </h2>
      <p class="text-xs text-slate-400 mb-6">
        Found {length(@discovered_files)} workflow files in {@repo_url}.
        Select the files you want to import.
      </p>

      <%= if Enum.empty?(@discovered_files) do %>
        <div class="text-center py-8 text-slate-400 italic text-xs">
          No workflow files discovered. Try a different repository or source type.
        </div>
      <% else %>
        <form phx-submit="step2_next">
          <div class="space-y-2 mb-6">
            <%= for file <- @discovered_files do %>
              <label class={[
                "flex items-center gap-3 p-3 rounded border cursor-pointer transition-all",
                "hover:bg-slate-50 border-[#d6e0e2]"
              ]}>
                <input type="checkbox" name="selected_files[]" value={file.path} class="rounded" checked />
                <div class="flex-1">
                  <span class="text-sm font-mono text-slate-700">{file.path}</span>
                  <span class="ml-2 text-[10px] text-slate-400">
                    {length(file.job_names)} jobs
                  </span>
                </div>
                <span class={[
                  "px-2 py-0.5 rounded text-[10px] font-bold",
                  if(@source_type == "github_actions", do: "bg-purple-50 text-purple-700", else: "bg-orange-50 text-orange-700")
                ]}>
                  {source_type_label(@source_type)}
                </span>
              </label>
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
              type="submit"
              class="flex-1 py-2.5 rounded bg-[#943a9e] hover:bg-purple-700 text-xs font-bold text-white shadow-sm transition-all"
            >
              Next: Configure Files <i class="fa fa-arrow-right ml-1"></i>
            </button>
          </div>
        </form>
      <% end %>
    </div>
    """
  end

  # ── Step 3: Per-file configuration ─────────────────────────────────────────

  defp step3_config(assigns) do
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
