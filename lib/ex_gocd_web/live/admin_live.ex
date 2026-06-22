defmodule ExGoCDWeb.AdminLive do
  @moduledoc """
  A feature-rich, high-fidelity Administration panel for GoCD.
  Aligned with original GoCD light theme, using white panels, light borders (#d6e0e2),
  and GoCD variables. Full-width layout with a top tab navigation bar.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.Accounts
  alias ExGoCD.Pipelines
  alias ExGoCD.AuditLog
  alias ExGoCD.AuditLog.Events
  alias ExGoCD.ConfigRepos

  @impl true
  def mount(_params, _session, socket) do
    unless socket.assigns[:is_user_admin] do
      {:ok,
       socket
       |> put_flash(:error, "You do not have administration permissions.")
       |> redirect(to: "/")}
    else
      empty_groups = []
      pipeline_groups = fetch_pipeline_groups(empty_groups)
      environments = fetch_environments_ui()

      config_repos =
        if use_mock?() do
          ExGoCD.MockData.config_repos()
        else
          ConfigRepos.list_config_repos()
        end

      # Load existing database users
      users = Accounts.list_users()

      # Audit log entries (mock or empty — AuditLogLive handles full UI)
      _audit_log_entries =
        if use_mock?() do
          ExGoCD.MockData.audit_log_entries()
        else
          []
        end

      plugins = []

      {:ok,
       socket
       |> assign(:empty_groups, empty_groups)
       |> assign(:pipeline_groups, pipeline_groups)
       |> assign(:filtered_groups, pipeline_groups)
       |> assign(:environments, environments)
       |> assign(:config_repos, config_repos)
       |> assign(:users, users)
       |> assign(:plugins, plugins)
       |> assign(:search_query, "")
       |> assign(:maintenance_mode, false)
       |> assign(:backup_status, "Idle") # Idle, Running, Completed
       |> assign(:backup_message, "")
       |> assign(:new_group_name, "")
       |> assign(:show_create_modal, false)
       # User modals assigns
       |> assign(:show_user_modal, false)
       |> assign(:user_modal_type, nil) # :add_user, :edit_roles
       |> assign(:selected_user, nil)
       |> assign(:user_form, %{"username" => "", "display_name" => "", "roles" => []})
       |> assign(:user_errors, %{})
       |> assign(:flash_info, nil)
       |> assign(:current_path, "/admin")
       # Audit log assigns
       |> assign(:audit_log_entries, [])
       |> assign(:audit_log_filters, %{})
       |> assign(:audit_log_loading, false)
       # Environment Modal assigns
       |> assign(:show_env_modal, false)
       |> assign(:env_modal_type, nil)
       |> assign(:selected_env, nil)
       |> assign(:env_form_name, "")
       |> assign(:env_form_pipelines, [])
       |> assign(:env_form_variables, [])
       |> assign(:available_pipelines, [])}
    end
  end

  defp use_mock? do
    System.get_env("USE_MOCK_DATA") == "true"
  end

  defp fetch_pipeline_groups(empty_groups) do
    db_pipelines = Pipelines.list_pipelines()

    db_groups =
      db_pipelines
      |> Enum.group_by(fn p -> p.group || "defaultGroup" end)
      |> Enum.map(fn {group_name, pipelines} ->
        %{
          name: group_name,
          pipelines: pipelines
        }
      end)

    db_group_names = MapSet.new(db_groups, & &1.name)
    merged_empty =
      empty_groups
      |> Enum.reject(&MapSet.member?(db_group_names, &1))
      |> Enum.map(fn name -> %{name: name, pipelines: []} end)

    result = db_groups ++ merged_empty

    if Enum.empty?(result) do
      [%{name: "defaultGroup", pipelines: []}]
    else
      result
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    path = URI.parse(url).path || ""
    mapped_tab = tab_from_path(path)

    socket =
      socket
      |> assign(:tab, mapped_tab)
      |> assign(:page_title, "GoCD Administration - #{tab_title(mapped_tab)}")
      |> assign(:current_path, path)

    socket =
      if mapped_tab == "audit_log" do
        load_audit_log(socket, %{})
      else
        socket
      end

    {:noreply, socket}
  end

  defp tab_from_path(path) do
    path
    |> String.split("/", trim: true)
    |> raw_tab_from_segments()
    |> map_tab()
  end

  defp raw_tab_from_segments(["go", "admin", tab_name | _]), do: tab_name
  defp raw_tab_from_segments(["admin", tab_name | _]), do: tab_name
  defp raw_tab_from_segments(_), do: "overview"

  defp map_tab(tab) do
    case tab do
      t when t in ["pipelines", "templates", "package_repositories"] -> "pipelines"
      t when t in ["environments", "elastic_agent_configurations"] -> "environments"
      t when t in ["config_repos", "scms"] -> "config_repos"
      t when t in ["server", "config_xml", "artifact_stores", "config", "maintenance_mode", "backup", "plugins"] ->
        "server"
      t when t in ["security", "users", "secret_configs", "admin_access_tokens"] -> "security"
      t when t in ["audit_log", "audit"] -> "audit_log"
      _ -> "overview"
    end
  end

  defp tab_title("config_repos"), do: "Config Repositories"
  defp tab_title("audit_log"), do: "Audit Log"
  defp tab_title(tab), do: String.capitalize(tab)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-page-wrapper min-h-screen bg-[#f4f8f9] text-[#333] font-sans pb-12">
      <!-- Page Header Panel -->
      <div class="bg-white border-b border-[#e9edef] px-6 py-4 flex flex-col sm:flex-row justify-between sm:items-center gap-4">
        <div class="flex items-center gap-2">
          <h1 class="text-xl font-semibold text-[#333] uppercase tracking-wide">
            <%= case @tab do %>
              <% "overview" -> %>Administration
              <% "pipelines" -> %>Pipelines
              <% "environments" -> %>Environments
              <% "config_repos" -> %>Config Repositories
              <% "server" -> %>Server Configuration
              <% "security" -> %>Security
              <% _ -> %>Admin
            <% end %>
          </h1>
          <a href="https://github.com/d-led/ex_gocd" target="_blank" class="text-[#943a9e] text-base hover:text-purple-800" aria-label="Help">
            <i class="fa-solid fa-circle-question"></i>
          </a>
        </div>

        <!-- Page Header Actions (Dynamic based on Tab) -->
        <div class="flex flex-wrap items-center gap-4">
          <%= if @tab == "pipelines" do %>
            <div class="relative">
              <span class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-400 text-xs">
                <i class="fa fa-search"></i>
              </span>
              <form phx-change="search_pipelines">
                <input type="text" name="query" value={@search_query} placeholder="Search for a pipeline name"
                       class="pl-8 pr-3 py-1.5 w-64 rounded border border-[#d6e0e2] text-xs focus:outline-none focus:border-[#943a9e] bg-white text-[#333]" />
              </form>
            </div>
            <button phx-click="toggle_create_modal" class="px-3 py-1.5 bg-white border border-[#943a9e] text-[#943a9e] rounded text-xs font-semibold hover:bg-purple-50 transition-all">
              <i class="fa fa-plus mr-1"></i> Create new pipeline group
            </button>
          <% end %>
          <%= if @tab == "security" do %>
            <button phx-click="open_add_user_modal" class="px-3 py-1.5 bg-white border border-[#943a9e] text-[#943a9e] rounded text-xs font-semibold hover:bg-purple-50 transition-all">
              <i class="fa fa-plus mr-1"></i> Add User
            </button>
          <% end %>
        </div>
      </div>

      <!-- Sub-Tab Navigation Bar -->
      <div class="bg-white border-b border-[#e9edef] px-6 py-2.5 flex flex-wrap gap-6 text-sm font-semibold shadow-sm">
        <.sub_tab_link active={@tab == "overview"} href="/admin/overview">Overview</.sub_tab_link>
        <.sub_tab_link active={@tab == "pipelines"} href="/admin/pipelines">Pipelines &amp; Groups</.sub_tab_link>
        <.sub_tab_link active={@tab == "environments"} href="/admin/environments">Environments</.sub_tab_link>
        <.sub_tab_link active={@tab == "config_repos"} href="/admin/config_repos">Config Repositories</.sub_tab_link>
        <.sub_tab_link active={@tab == "server"} href="/admin/server">Server Configuration</.sub_tab_link>
        <.sub_tab_link active={@tab == "security"} href="/admin/security">Security &amp; Users</.sub_tab_link>
        <.sub_tab_link active={@tab == "audit_log"} href="/admin/audit_log">Audit Log</.sub_tab_link>
      </div>

      <!-- Main Layout Body (Centered Content) -->
      <div class="max-w-[1400px] mx-auto px-6 py-6">
        <%= if @flash_info do %>
          <div class="mb-5 bg-[#dbf1d9] border border-[#a3d7a8] text-[#298a4c] px-4 py-3 rounded flex justify-between items-center text-sm shadow-sm" role="alert">
            <span class="font-medium">{@flash_info}</span>
            <button phx-click="clear_flash" class="text-[#298a4c] hover:text-emerald-900">
              <i class="fa fa-times"></i>
            </button>
          </div>
        <% end %>

        <%= case @tab do %>
          <% "overview" -> %>
            <.overview_tab
              pipeline_groups={@pipeline_groups}
              environments={@environments}
              config_repos={@config_repos}
              users={@users}
              plugins={@plugins}
              maintenance_mode={@maintenance_mode}
            />
          <% "pipelines" -> %>
            <.pipelines_tab
              filtered_groups={@filtered_groups}
              search_query={@search_query}
              new_group_name={@new_group_name}
              show_create_modal={@show_create_modal}
            />
          <% "environments" -> %>
            <.environments_tab environments={@environments} />
          <% "config_repos" -> %>
            <.config_repos_tab config_repos={@config_repos} />
          <% "server" -> %>
            <.server_tab
              maintenance_mode={@maintenance_mode}
              backup_status={@backup_status}
              backup_message={@backup_message}
              plugins={@plugins}
            />
          <% "security" -> %>
            <.security_tab users={@users} />
          <% "audit_log" -> %>
            <.audit_log_tab
              entries={@audit_log_entries}
              filters={@audit_log_filters}
              loading={@audit_log_loading}
            />
          <% _ -> %>
            <div class="text-center py-12 bg-white border border-[#d6e0e2] rounded shadow-sm">
              <h3 class="text-lg font-bold">Section Not Found</h3>
              <p class="text-slate-500 mt-2">The requested admin section could not be loaded.</p>
            </div>
        <% end %>
      </div>

      <%= if @show_user_modal do %>
        <.user_modal_layer type={@user_modal_type} form={@user_form} errors={@user_errors} user={@selected_user} />
      <% end %>

      <%= if @show_env_modal do %>
        <.env_modal_layer
          type={@env_modal_type}
          name={@env_form_name}
          available_pipelines={@available_pipelines}
          selected_pipelines={@env_form_pipelines}
          variables={@env_form_variables}
          env={@selected_env}
        />
      <% end %>
    </div>
    """
  end

  # --- Subcomponents ---

  defp sub_tab_link(assigns) do
    ~H"""
    <a href={@href} class={["pb-2 border-b-2 transition-all font-semibold text-xs uppercase tracking-wide",
                            if(@active, do: "border-[#943a9e] text-[#943a9e]",
                                       else: "border-transparent text-slate-500 hover:text-[#333] hover:border-slate-350")]}>
      {render_slot(@inner_block)}
    </a>
    """
  end

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-white rounded border border-[#d6e0e2] p-5 flex items-center gap-4 shadow-sm">
      <div class="w-12 h-12 rounded bg-slate-100 flex items-center justify-center shrink-0">
        <i class={["fa text-xl text-[#943a9e]", @icon]}></i>
      </div>
      <div>
        <p class="text-[10px] text-slate-400 font-bold uppercase tracking-wider">{@title}</p>
        <p class="text-xl font-bold mt-1 text-[#333]">{@value}</p>
        <p class="text-xs text-slate-500 mt-0.5">{@sub}</p>
      </div>
    </div>
    """
  end

  # --- Tab Renderings ---

  defp overview_tab(assigns) do
    assigns = assigns
      |> assign(:pipeline_count, Enum.reduce(assigns.pipeline_groups, 0, fn g, acc -> acc + length(g.pipelines) end))
      |> assign(:group_count, length(assigns.pipeline_groups))

    ~H"""
    <div class="space-y-6">
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        <.stat_card icon="fa-network-wired" title="Pipeline Groups" value={"#{@group_count}"} sub={"#{@pipeline_count} total pipelines"} />
        <.stat_card icon="fa-earth-americas" title="Environments" value={"#{length(@environments)}"} sub="Assigned to agents" />
        <.stat_card icon="fa-git-alt" title="Config Repos" value={"#{length(@config_repos)}"} sub="Pipelines-as-code repos" />
        <.stat_card icon="fa-users" title="Active Users" value={"#{length(@users)}"} sub="Authorized administrators" />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Server Status -->
        <div class="bg-white rounded border border-[#d6e0e2] p-5 shadow-sm">
          <h3 class="text-sm font-bold border-b border-[#e9edef] pb-3 flex items-center gap-2 text-slate-700">
            <i class="fa fa-server text-[#943a9e]"></i> Server Status
          </h3>
          <div class="mt-4 space-y-3.5 text-xs text-slate-600">
            <div class="flex justify-between">
              <span>Server State:</span>
              <span class="font-semibold text-emerald-600">Running</span>
            </div>
            <div class="flex justify-between">
              <span>Maintenance Mode:</span>
              <span class={["font-bold", if(@maintenance_mode, do: "text-amber-600", else: "text-slate-500")]}>
                {if @maintenance_mode, do: "Enabled (Read-only)", else: "Disabled"}
              </span>
            </div>
            <div class="flex justify-between">
              <span>API Database:</span>
              <span class="font-semibold text-emerald-600">Connected (PostgreSQL)</span>
            </div>
            <div class="flex justify-between">
              <span>Registered Plugins:</span>
              <span class="font-semibold text-[#943a9e]">{length(@plugins)} Active Plugins</span>
            </div>
          </div>
        </div>

        <!-- Quick Actions -->
        <div class="bg-white rounded border border-[#d6e0e2] p-5 shadow-sm">
          <h3 class="text-sm font-bold border-b border-[#e9edef] pb-3 flex items-center gap-2 text-slate-700">
            <i class="fa fa-bolt text-amber-500"></i> Operations Control
          </h3>
          <div class="mt-4 space-y-4">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-xs font-bold text-slate-700">Maintenance Mode</p>
                <p class="text-[11px] text-slate-400 mt-0.5">Pause all pipeline builds for system maintenance.</p>
              </div>
              <button phx-click="toggle_maintenance_mode"
                      class={["px-3 py-1.5 rounded text-xs font-semibold border transition-all",
                              if(@maintenance_mode, do: "bg-amber-600 border-amber-500 text-white hover:bg-amber-500",
                                         else: "bg-slate-100 border-slate-350 text-slate-700 hover:bg-slate-200")]}>
                {if @maintenance_mode, do: "Disable", else: "Enable"}
              </button>
            </div>

            <div class="flex items-center justify-between border-t border-[#e9edef] pt-4">
              <div>
                <p class="text-xs font-bold text-slate-700">Config Backup</p>
                <p class="text-[11px] text-slate-400 mt-0.5">Create a backup snapshot of GoCD server config database.</p>
              </div>
              <a href="/admin/server" class="px-3 py-1.5 rounded text-xs font-semibold bg-[#943a9e] hover:bg-purple-700 border border-purple-700 text-white text-center transition-all shadow-sm">
                Backup Server
              </a>
            </div>

            <div class="flex items-center justify-between border-t border-[#e9edef] pt-4">
              <div>
                <p class="text-xs font-bold text-slate-700">Cleanup Stuck Jobs</p>
                <p class="text-[11px] text-slate-400 mt-0.5">Cancel all Scheduled/Building jobs that are stuck.</p>
              </div>
              <button phx-click="cleanup_stuck_jobs"
                      class="px-3 py-1.5 rounded text-xs font-semibold bg-red-600 border border-red-500 text-white hover:bg-red-500 transition-all shadow-sm">
                Cleanup Now
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp pipelines_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Add group modal/form -->
      <%= if @show_create_modal do %>
        <form phx-submit="create_pipeline_group" class="bg-white rounded border border-[#d6e0e2] p-5 shadow flex flex-col sm:flex-row gap-4 items-end max-w-2xl">
          <div class="flex-grow">
            <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">New Pipeline Group Name</label>
            <input type="text" name="name" value={@new_group_name} placeholder="e.g. stagingGroup" required
                   class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs text-slate-700 focus:outline-none focus:border-[#943a9e]" />
          </div>
          <div class="flex gap-2">
            <button type="submit" class="px-4 py-2 rounded bg-[#943a9e] hover:bg-purple-700 text-white text-xs font-semibold border border-purple-700 shadow-sm transition-all">
              <i class="fa fa-plus mr-1"></i> Add Group
            </button>
            <button type="button" phx-click="toggle_create_modal" class="px-4 py-2 rounded bg-slate-100 border border-slate-350 text-slate-700 text-xs font-semibold hover:bg-slate-200">
              Cancel
            </button>
          </div>
        </form>
      <% end %>

      <!-- Pipeline Group Cards -->
      <div class="space-y-6">
        <%= for group <- @filtered_groups do %>
          <div class="bg-white rounded border border-[#d6e0e2] overflow-hidden shadow-sm">
            <div class="bg-[#e7eef0] px-5 py-3 border-b border-[#d6e0e2] flex justify-between items-center">
              <div class="text-xs text-slate-600">
                Pipeline Group: <span class="font-bold text-slate-800">{group.name}</span>
              </div>
              <div class="flex items-center gap-2">
                <button phx-click="add_pipeline_to_group" phx-value-group={group.name} class="px-3 py-1 bg-[#943a9e] text-white rounded text-[11px] font-bold hover:bg-purple-700 transition-all shadow-sm">
                  <i class="fa fa-plus mr-1"></i> Add new pipeline
                </button>
                <button class="p-1 w-7 h-7 border border-[#d6e0e2] bg-white text-slate-600 rounded hover:bg-slate-50 text-xs flex items-center justify-center" title="Edit Group">
                  <i class="fa fa-edit"></i>
                </button>
                <button phx-click="delete_pipeline_group" phx-value-name={group.name} class="p-1 w-7 h-7 border border-[#d6e0e2] bg-white text-rose-500 rounded hover:bg-slate-50 text-xs flex items-center justify-center" title="Delete Group">
                  <i class="fa fa-trash-can"></i>
                </button>
              </div>
            </div>

            <div class="divide-y divide-[#e9edef]">
              <%= if Enum.empty?(group.pipelines) do %>
                <div class="p-6 text-center text-slate-400 text-xs italic bg-white">
                  No pipelines defined in this group.
                </div>
              <% else %>
                <%= for pipe <- group.pipelines do %>
                  <div class="px-5 py-3 flex justify-between items-center bg-white hover:bg-slate-50/30">
                    <span class="text-sm font-medium text-slate-700">{pipe.name}</span>
                    <div class="flex items-center gap-1.5">
                      <a href={"/pipeline/activity/#{pipe.name}"} class="w-7 h-7 border border-[#d6e0e2] bg-white text-[#943a9e] rounded hover:bg-slate-50 flex items-center justify-center text-[13px]" title="Activity">
                        <i class="fa fa-chart-line"></i>
                      </a>
                      <a href={"/go/admin/pipelines/#{pipe.name}/edit/general"} class="w-7 h-7 border border-[#d6e0e2] bg-white text-slate-500 rounded hover:bg-slate-50 flex items-center justify-center text-[13px]" title="Edit pipeline">
                        <i class="fa fa-pencil"></i>
                      </a>
                      <button class="w-7 h-7 border border-[#d6e0e2] bg-white text-slate-500 rounded hover:bg-slate-50 flex items-center justify-center text-[13px]" title="Move pipeline">
                        <i class="fa fa-arrow-right"></i>
                      </button>
                      <button class="w-7 h-7 border border-[#d6e0e2] bg-white text-slate-500 rounded hover:bg-slate-50 flex items-center justify-center text-[13px]" title="Download configuration">
                        <i class="fa fa-download"></i>
                      </button>
                      <button class="w-7 h-7 border border-[#d6e0e2] bg-white text-slate-500 rounded hover:bg-slate-50 flex items-center justify-center text-[13px]" title="Clone pipeline">
                        <i class="fa fa-clone"></i>
                      </button>
                      <button phx-click="delete_pipeline" phx-value-name={pipe.name} data-confirm="Are you sure you want to delete this pipeline?" class="w-7 h-7 border border-[#d6e0e2] bg-white text-rose-500 rounded hover:bg-slate-50 flex items-center justify-center text-[13px]" title="Delete pipeline">
                        <i class="fa fa-trash-can"></i>
                      </button>
                      <button class="w-7 h-7 border border-[#d6e0e2] bg-white text-slate-500 rounded hover:bg-slate-50 flex items-center justify-center text-[13px]" title="Extract template">
                        <i class="fa fa-plus"></i>
                      </button>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp environments_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-between items-center mb-2">
        <h2 class="text-sm font-bold text-slate-700">Environment Configuration</h2>
        <button phx-click="open_add_env_modal" class="px-2.5 py-1 bg-[#943a9e] hover:bg-purple-700 text-white text-[11px] font-bold rounded shadow-sm">
          <i class="fa fa-plus mr-1"></i> Add Environment
        </button>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <%= for env <- @environments do %>
          <div class="bg-white rounded border border-[#d6e0e2] overflow-hidden shadow-sm">
            <div class="bg-[#e7eef0] px-5 py-3 border-b border-[#d6e0e2] flex justify-between items-center">
              <h3 class="text-xs font-bold text-slate-700 flex items-center gap-2">
                <i class="fa fa-earth-americas text-[#943a9e]"></i> {env.name}
              </h3>
              <div class="flex items-center gap-3">
                <span class="text-[10px] bg-slate-200 px-2 py-0.5 rounded font-bold text-slate-600">
                  {env.agents} Active Agents
                </span>
                <button phx-click="delete_environment_ui" phx-value-name={env.name} data-confirm="Are you sure you want to delete this environment?" class="text-rose-500 hover:text-rose-700 text-xs cursor-pointer border-0 bg-transparent" title="Delete Environment">
                  <i class="fa fa-trash-can"></i>
                </button>
              </div>
            </div>

            <div class="p-5 space-y-3">
              <span class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider">Assigned Pipelines</span>
              <div class="flex flex-wrap gap-2">
                <%= for pipe <- env.pipelines do %>
                  <span class="text-xs bg-slate-50 border border-[#e9edef] px-2 py-1 rounded text-slate-600 font-medium">
                    {pipe}
                  </span>
                <% end %>
                <%= if Enum.empty?(env.pipelines) do %>
                  <span class="text-xs text-slate-400 italic">No pipelines assigned</span>
                <% end %>
              </div>

              <div class="flex justify-end gap-3 pt-3 border-t border-[#e9edef]">
                <button phx-click="open_edit_env_modal" phx-value-name={env.name} class="text-xs text-[#943a9e] hover:text-purple-800 font-bold border-0 bg-transparent cursor-pointer">
                  Configure Environment
                </button>
              </div>
            </div>
          </div>
        <% end %>
        <%= if Enum.empty?(@environments) do %>
          <div class="col-span-2 text-center py-12 bg-white border border-[#d6e0e2] rounded shadow-sm text-slate-400 italic text-xs">
            No environments configured.
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp config_repos_tab(assigns) do
    ~H"""
    <div class="bg-white rounded border border-[#d6e0e2] overflow-hidden shadow-sm">
      <div class="p-4 flex justify-between items-center border-b border-[#d6e0e2]">
        <span class="text-sm font-bold text-slate-700">
          <i class="fa fa-code-fork mr-2 text-[#943a9e]"></i>Config Repositories
        </span>
        <a href="/admin/config_repos/new" class="px-3 py-1.5 rounded bg-[#943a9e] hover:bg-purple-700 text-xs font-bold text-white shadow-sm transition-all">
          <i class="fa fa-plus mr-1"></i> Add Config Repo
        </a>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full text-left text-xs text-slate-600">
          <thead class="bg-[#e7eef0] text-[10px] font-bold text-slate-500 uppercase border-b border-[#d6e0e2]">
            <tr>
              <th class="px-5 py-3.5">Repo URL</th>
              <th class="px-5 py-3.5">Source Type</th>
              <th class="px-5 py-3.5">Branch</th>
              <th class="px-5 py-3.5">Status</th>
              <th class="px-5 py-3.5">Last Sync</th>
              <th class="px-5 py-3.5 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[#e9edef] bg-white">
            <%= if Enum.empty?(@config_repos) do %>
              <tr>
                <td colspan="6" class="px-5 py-12 text-center text-slate-400 italic text-xs">
                  No config repositories configured. Add one to get started.
                </td>
              </tr>
            <% end %>
            <%= for repo <- @config_repos do %>
              <tr class="hover:bg-slate-50/50">
                <td class="px-5 py-4 font-mono text-[11px] text-slate-500 max-w-xs truncate" title={repo.url}>
                  {repo.url}
                </td>
                <td class="px-5 py-4">
                  <span class={["inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-bold", source_type_badge_class(repo.source_type)]}>
                    {source_type_label(repo.source_type)}
                  </span>
                </td>
                <td class="px-5 py-4 text-slate-600">{repo.branch}</td>
                <td class="px-5 py-4">
                  <span class={["inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-bold", status_class(repo)]}>
                    <span class={["w-1.5 h-1.5 rounded-full", status_dot_class(repo)]}></span>
                    {status_label(repo)}
                  </span>
                </td>
                <td class="px-5 py-4 text-slate-500">
                  {if repo.last_parsed_at, do: Calendar.strftime(repo.last_parsed_at, "%Y-%m-%d %H:%M"), else: "—"}
                </td>
                <td class="px-5 py-4 text-right">
                  <button phx-click="sync_config_repo" phx-value-id={repo.id} class="text-xs text-[#943a9e] hover:text-purple-800 font-bold mr-3">
                    <i class="fa fa-sync mr-1"></i> Sync
                  </button>
                  <button phx-click="delete_config_repo" phx-value-id={repo.id} class="text-xs text-slate-500 hover:text-red-600" data-confirm="Delete this config repo? Pipelines will not be deleted.">
                    Delete
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp source_type_label("github_actions"), do: "GitHub Actions"
  defp source_type_label("gitlab_ci"), do: "GitLab CI"
  defp source_type_label(_), do: "GoCD Pipeline"

  defp source_type_badge_class("github_actions"), do: "bg-purple-50 text-purple-700 border border-purple-200"
  defp source_type_badge_class("gitlab_ci"), do: "bg-orange-50 text-orange-700 border border-orange-200"
  defp source_type_badge_class(_), do: "bg-emerald-50 text-emerald-700 border border-emerald-200"

  defp status_label(%{error_message: err}) when is_binary(err) and err != "", do: "Error"
  defp status_label(%{last_parsed_at: nil}), do: "Never Synced"
  defp status_label(_), do: "Good"

  defp status_class(%{error_message: err}) when is_binary(err) and err != "", do: "bg-red-50 text-red-600 border border-red-200"
  defp status_class(%{last_parsed_at: nil}), do: "bg-yellow-50 text-yellow-600 border border-yellow-200"
  defp status_class(_), do: "bg-emerald-50 text-emerald-600 border border-emerald-200"

  defp status_dot_class(%{error_message: err}) when is_binary(err) and err != "", do: "bg-red-500"
  defp status_dot_class(%{last_parsed_at: nil}), do: "bg-yellow-500"
  defp status_dot_class(_), do: "bg-emerald-500"

  defp server_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Backups -->
      <div class="bg-white rounded border border-[#d6e0e2] p-5 shadow-sm space-y-4">
        <h3 class="text-sm font-bold text-slate-700 border-b border-[#e9edef] pb-3 flex items-center gap-2">
          <i class="fa fa-cloud-arrow-up text-[#943a9e]"></i> Backup Configuration Database
        </h3>
        <p class="text-xs text-slate-500">
          A configuration backup captures the configuration XML file, local database records, and secure variables settings.
        </p>

        <div class="bg-slate-50 p-4 rounded border border-[#e9edef] space-y-2 text-xs">
          <div class="flex justify-between">
            <span class="text-slate-500 font-medium">Backup Status:</span>
            <span class={["font-bold",
                          case @backup_status do
                            "Running" -> "text-amber-600"
                            "Completed" -> "text-emerald-600"
                            _ -> "text-slate-500"
                          end]}>
              {@backup_status}
            </span>
          </div>
          <%= if @backup_message != "" do %>
            <div class="text-slate-600 mt-2 border-t border-[#e9edef] pt-2 font-mono text-[11px] leading-relaxed">
              {@backup_message}
            </div>
          <% end %>
        </div>

        <button phx-click="trigger_backup" disabled={@backup_status == "Running"}
                class="w-full py-2 rounded bg-[#943a9e] hover:bg-purple-700 disabled:bg-slate-200 text-xs font-semibold text-white border border-purple-700 disabled:border-slate-300 disabled:text-slate-400 shadow-sm transition-all flex items-center justify-center gap-2">
          <%= if @backup_status == "Running" do %>
            <i class="fa fa-spinner animate-spin"></i> Running Backup...
          <% else %>
            <i class="fa fa-cloud-arrow-up"></i> Start Backup Now
          <% end %>
        </button>
      </div>

      <!-- Plugins -->
      <div class="bg-white rounded border border-[#d6e0e2] p-5 shadow-sm space-y-4">
        <h3 class="text-sm font-bold text-slate-700 border-b border-[#e9edef] pb-3 flex items-center gap-2">
          <i class="fa fa-cubes text-[#943a9e]"></i> Active Plugins
        </h3>
        <p class="text-xs text-slate-500">
          Active plugins providing custom material types, artifact store plugins, and slack integrations.
        </p>

        <div class="divide-y divide-[#e9edef] bg-white">
          <%= for plugin <- @plugins do %>
            <div class="py-3 flex justify-between items-center text-xs">
              <div>
                <p class="font-bold text-slate-700">{plugin.name}</p>
                <p class="text-slate-400 font-mono text-[10px] mt-0.5">{plugin.id}</p>
              </div>
              <div class="text-right">
                <span class="text-slate-500 font-semibold">v{plugin.version}</span>
                <span class="ml-2 bg-emerald-50 text-emerald-600 border border-emerald-200 px-1.5 py-0.5 rounded text-[10px] font-bold">
                  Active
                </span>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp user_modal_layer(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
      <div class="bg-white rounded border border-[#d6e0e2] shadow-xl w-full max-w-md overflow-hidden">
        <div class="bg-[#e7eef0] border-b border-[#d6e0e2] px-5 py-3 flex justify-between items-center">
          <h3 class="text-xs font-bold uppercase tracking-wider text-slate-700">
            <%= if @type == :add_user, do: "Add New User", else: "Manage User Roles" %>
          </h3>
          <button type="button" phx-click="close_user_modal" class="text-slate-400 hover:text-slate-600">
            <i class="fa fa-times"></i>
          </button>
        </div>

        <form phx-submit="save_user" class="p-6 space-y-4 text-xs">
          <%= if @type == :add_user do %>
            <div>
              <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Username</label>
              <input type="text" name="username" value={@form["username"]} required
                     class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs text-[#333] focus:outline-none focus:border-[#943a9e]" />
              <%= if error = Map.get(@errors, :username) do %>
                <p class="text-rose-500 mt-1 text-[11px] font-semibold">{error}</p>
              <% end %>
            </div>
          <% end %>

          <div>
            <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Display Name</label>
            <input type="text" name="display_name" value={@form["display_name"]} required
                   class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs text-[#333] focus:outline-none focus:border-[#943a9e]" />
            <%= if error = Map.get(@errors, :display_name) do %>
              <p class="text-rose-500 mt-1 text-[11px] font-semibold">{error}</p>
            <% end %>
          </div>

          <div>
            <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Assign Roles</label>
            <div class="space-y-2.5 mt-2 bg-slate-50 p-4 rounded border border-[#e9edef]">
              <label class="flex items-center gap-2.5 font-medium text-slate-700 cursor-pointer">
                <input type="checkbox" name="roles[]" value="admin" checked={"admin" in (@form["roles"] || [])}
                       class="rounded border-[#d6e0e2] text-[#943a9e] focus:ring-[#943a9e]" />
                <span>Administrator (Full admin access)</span>
              </label>
              <label class="flex items-center gap-2.5 font-medium text-slate-700 cursor-pointer">
                <input type="checkbox" name="roles[]" value="developer" checked={"developer" in (@form["roles"] || [])}
                       class="rounded border-[#d6e0e2] text-[#943a9e] focus:ring-[#943a9e]" />
                <span>Developer (Pipeline configuration and execution)</span>
              </label>
              <label class="flex items-center gap-2.5 font-medium text-slate-700 cursor-pointer">
                <input type="checkbox" name="roles[]" value="viewer" checked={"viewer" in (@form["roles"] || [])}
                       class="rounded border-[#d6e0e2] text-[#943a9e] focus:ring-[#943a9e]" />
                <span>Viewer (Read-only observation)</span>
              </label>
            </div>
          </div>

          <div class="flex justify-end gap-3 pt-4 border-t border-[#e9edef]">
            <button type="submit" class="px-4 py-2 bg-[#943a9e] hover:bg-purple-700 text-white font-bold rounded shadow-sm">
              Save User
            </button>
            <button type="button" phx-click="close_user_modal" class="px-4 py-2 bg-white border border-slate-350 text-slate-700 rounded hover:bg-slate-50 font-semibold">
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp security_tab(assigns) do
    ~H"""
    <div class="bg-white rounded border border-[#d6e0e2] overflow-hidden shadow-sm">
      <div class="overflow-x-auto">
        <table class="w-full text-left text-xs text-slate-600 font-sans">
          <thead class="bg-[#e7eef0] text-[10px] font-bold text-slate-500 uppercase border-b border-[#d6e0e2]">
            <tr>
              <th class="px-5 py-3.5">Username</th>
              <th class="px-5 py-3.5">Display Name</th>
              <th class="px-5 py-3.5">Assigned Roles</th>
              <th class="px-5 py-3.5">Status</th>
              <th class="px-5 py-3.5 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[#e9edef] bg-white">
            <%= for user <- @users do %>
              <tr class="hover:bg-slate-50/50">
                <td class="px-5 py-4 font-bold text-slate-700 font-mono">{user.username}</td>
                <td class="px-5 py-4 text-slate-600">{user.display_name}</td>
                <td class="px-5 py-4 flex gap-1.5 flex-wrap">
                  <%= if Enum.empty?(user.roles) do %>
                    <span class="text-xs text-slate-400 italic">None</span>
                  <% else %>
                    <%= for role <- user.roles do %>
                      <span class="text-[10px] bg-slate-50 border border-[#e9edef] px-2 py-0.5 rounded text-slate-600 font-semibold">
                        {role}
                      </span>
                    <% end %>
                  <% end %>
                </td>
                <td class="px-5 py-4">
                  <%= if user.status == "Active" do %>
                    <span class="inline-flex items-center gap-1 bg-emerald-50 text-emerald-600 border border-emerald-200 px-2 py-0.5 rounded text-[10px] font-bold">
                      <span class="w-1.5 h-1.5 bg-emerald-500 rounded-full"></span>
                      Active
                    </span>
                  <% else %>
                    <span class="inline-flex items-center gap-1 bg-rose-50 text-rose-600 border border-rose-200 px-2 py-0.5 rounded text-[10px] font-bold">
                      <span class="w-1.5 h-1.5 bg-rose-500 rounded-full"></span>
                      Disabled
                    </span>
                  <% end %>
                </td>
                <td class="px-5 py-4 text-right">
                  <button phx-click="open_edit_user_roles_modal" phx-value-id={user.id} class="text-xs text-[#943a9e] hover:text-purple-800 font-bold mr-3">
                    Manage Roles
                  </button>
                  <button phx-click="toggle_user_status" phx-value-id={user.id} class={["text-xs mr-3 font-semibold", if(user.status == "Active", do: "text-slate-500 hover:text-slate-800", else: "text-emerald-500 hover:text-emerald-700")]}>
                    {if user.status == "Active", do: "Disable", else: "Enable"}
                  </button>
                  <button phx-click="delete_user" phx-value-id={user.id} data-confirm="Are you sure you want to delete this user?" class="text-xs text-rose-500 hover:text-rose-700">
                    Delete
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # --- Event Handlers ---

  @impl true
  def handle_event("sync_config_repo", %{"id" => id}, socket) do
    id = String.to_integer(id)
    case ConfigRepos.get_config_repo(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Config repo not found.")}
      repo ->
        # Trigger a re-sync (in future: open wizard)
        {:ok, updated} = ConfigRepos.update_config_repo(repo, %{last_parsed_at: DateTime.utc_now()})
        repos = ConfigRepos.list_config_repos()
        {:noreply,
         socket
         |> assign(:config_repos, repos)
         |> put_flash(:info, "Config repo '#{updated.url}' synced.")}
    end
  end

  @impl true
  def handle_event("delete_config_repo", %{"id" => id}, socket) do
    id = String.to_integer(id)
    case ConfigRepos.get_config_repo(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Config repo not found.")}
      repo ->
        {:ok, _} = ConfigRepos.delete_config_repo(repo)
        repos = ConfigRepos.list_config_repos()
        {:noreply,
         socket
         |> assign(:config_repos, repos)
         |> put_flash(:info, "Config repo deleted.")}
    end
  end

  @impl true
  def handle_event("clear_flash", _params, socket) do
    {:noreply, assign(socket, :flash_info, nil)}
  end

  @impl true
  def handle_event("toggle_maintenance_mode", _params, socket) do
    new_state = !socket.assigns.maintenance_mode
    message = if new_state, do: "Server entered maintenance mode.", else: "Server left maintenance mode."
    {:noreply,
     socket
     |> assign(:maintenance_mode, new_state)
     |> assign(:flash_info, message)}
  end

  @impl true
  def handle_event("trigger_backup", _params, socket) do
    # Simulate backup start
    Process.send_after(self(), :backup_complete, 1500)
    {:noreply,
     socket
     |> assign(:backup_status, "Running")
     |> assign(:backup_message, "Config backup started at #{DateTime.utc_now() |> DateTime.to_string()}...")}
  end

  @impl true
  def handle_event("search_pipelines", %{"query" => query}, socket) do
    cleaned = String.trim(query)
    filtered =
      if cleaned == "" do
        socket.assigns.pipeline_groups
      else
        socket.assigns.pipeline_groups
        |> Enum.map(&filter_group_pipelines(&1, cleaned))
        |> Enum.reject(&Enum.empty?(&1.pipelines))
      end

    {:noreply,
     socket
     |> assign(:search_query, cleaned)
     |> assign(:filtered_groups, filtered)}
  end

  @impl true
  def handle_event("toggle_create_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, !socket.assigns.show_create_modal)}
  end

  @impl true
  def handle_event("create_pipeline_group", %{"name" => name}, socket) do
    cleaned = String.trim(name)
    existing_group = Enum.find(socket.assigns.pipeline_groups, &(&1.name == cleaned))

    cond do
      cleaned == "" ->
        {:noreply, socket}

      existing_group ->
        {:noreply, assign(socket, :flash_info, "Pipeline group '#{cleaned}' already exists.")}

      true ->
        empty_groups = [cleaned | socket.assigns.empty_groups]
        groups = fetch_pipeline_groups(empty_groups)

        {:noreply,
         socket
         |> assign(:empty_groups, empty_groups)
         |> assign(:pipeline_groups, groups)
         |> assign(:filtered_groups, groups)
         |> assign(:new_group_name, "")
         |> assign(:show_create_modal, false)
         |> assign(:flash_info, "Pipeline group '#{cleaned}' created successfully.")}
    end
  end

  @impl true
  def handle_event("delete_pipeline_group", %{"name" => name}, socket) do
    socket.assigns.pipeline_groups
    |> Enum.find(&(&1.name == name))
    |> maybe_delete_group_pipelines()

    empty_groups = Enum.reject(socket.assigns.empty_groups, &(&1 == name))
    groups = fetch_pipeline_groups(empty_groups)

    {:noreply,
     socket
     |> assign(:empty_groups, empty_groups)
     |> assign(:pipeline_groups, groups)
     |> assign(:filtered_groups, groups)
     |> assign(:flash_info, "Pipeline group '#{name}' was deleted.")}
  end

  @impl true
  def handle_event("delete_pipeline", %{"name" => name}, socket) do
    case Pipelines.delete_pipeline_by_name(name) do
      {:ok, _} ->
        groups = fetch_pipeline_groups(socket.assigns.empty_groups)
        {:noreply,
         socket
         |> assign(:pipeline_groups, groups)
         |> assign(:filtered_groups, groups)
         |> assign(:flash_info, "Pipeline '#{name}' was deleted.")}
      {:error, _reason} ->
        {:noreply, assign(socket, :flash_info, "Failed to delete pipeline '#{name}'.")}
    end
  end

  @impl true
  def handle_event("add_pipeline_to_group", %{"group" => group_name}, socket) do
    {:noreply, push_navigate(socket, to: "/go/admin/pipelines/new?group=#{group_name}")}
  end

  @impl true
  def handle_event("open_add_user_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_user_modal, true)
     |> assign(:user_modal_type, :add_user)
     |> assign(:selected_user, nil)
     |> assign(:user_form, %{"username" => "", "display_name" => "", "roles" => []})
     |> assign(:user_errors, %{})}
  end

  @impl true
  def handle_event("open_edit_user_roles_modal", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    {:noreply,
     socket
     |> assign(:show_user_modal, true)
     |> assign(:user_modal_type, :edit_roles)
     |> assign(:selected_user, user)
     |> assign(:user_form, %{
       "display_name" => user.display_name,
       "roles" => user.roles || []
     })
     |> assign(:user_errors, %{})}
  end

  @impl true
  def handle_event("close_user_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_user_modal, false)
     |> assign(:user_modal_type, nil)
     |> assign(:selected_user, nil)
     |> assign(:user_form, %{})
     |> assign(:user_errors, %{})}
  end

  @impl true
  def handle_event("save_user", params, socket) do
    roles = params["roles"] || []

    case socket.assigns.user_modal_type do
      :add_user -> save_new_user(socket, params, roles)
      :edit_roles -> save_user_roles(socket, params, roles)
    end
  end

  @impl true
  def handle_event("toggle_user_status", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    new_status = if user.status == "Active", do: "Disabled", else: "Active"
    case Accounts.update_user(user, %{status: new_status}) do
      {:ok, _} ->
        users = Accounts.list_users()
        {:noreply,
         socket
         |> assign(:users, users)
         |> assign(:flash_info, "User status updated successfully.")}
      {:error, _} ->
        {:noreply, assign(socket, :flash_info, "Failed to update user status.")}
    end
  end

  @impl true
  def handle_event("delete_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    case Accounts.delete_user(user) do
      {:ok, _} ->
        users = Accounts.list_users()
        {:noreply,
         socket
         |> assign(:users, users)
         |> assign(:flash_info, "User deleted successfully.")}
      {:error, _} ->
        {:noreply, assign(socket, :flash_info, "Failed to delete user.")}
    end
  end

  # --- UI Environments Event Handlers ---

  @impl true
  def handle_event("open_add_env_modal", _params, socket) do
    available = load_available_pipelines()
    {:noreply,
     socket
     |> assign(:show_env_modal, true)
     |> assign(:env_modal_type, :create)
     |> assign(:selected_env, nil)
     |> assign(:env_form_name, "")
     |> assign(:env_form_pipelines, [])
     |> assign(:env_form_variables, [])
     |> assign(:available_pipelines, available)}
  end

  @impl true
  def handle_event("close_env_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_env_modal, false)
     |> assign(:env_modal_type, nil)
     |> assign(:selected_env, nil)}
  end

  @impl true
  def handle_event("open_edit_env_modal", %{"name" => name}, socket) do
    case ExGoCD.Environments.get_environment_by_name(name) do
      nil ->
        {:noreply, put_flash(socket, :error, "Environment not found.")}

      env ->
        available = load_available_pipelines(env.id)
        selected_pipes = Enum.map(env.pipelines, & &1.name)
        vars = map_variables_for_modal(env.environment_variables)

        {:noreply,
         socket
         |> assign(:show_env_modal, true)
         |> assign(:env_modal_type, :edit)
         |> assign(:selected_env, env)
         |> assign(:env_form_name, env.name)
         |> assign(:env_form_pipelines, selected_pipes)
         |> assign(:env_form_variables, vars)
         |> assign(:available_pipelines, available)}
    end
  end

  @impl true
  def handle_event("add_env_var_row", _params, socket) do
    vars = socket.assigns.env_form_variables ++ [%{"name" => "", "value" => "", "secure" => false}]
    {:noreply, assign(socket, :env_form_variables, vars)}
  end

  @impl true
  def handle_event("remove_env_var_row", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    vars = List.delete_at(socket.assigns.env_form_variables, idx)
    {:noreply, assign(socket, :env_form_variables, vars)}
  end

  @impl true
  def handle_event("toggle_var_secure", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    vars =
      List.update_at(socket.assigns.env_form_variables, idx, fn var ->
        sec = Map.get(var, "secure") || Map.get(var, :secure) || false
        Map.put(var, "secure", !sec)
      end)
    {:noreply, assign(socket, :env_form_variables, vars)}
  end

  @impl true
  def handle_event("delete_environment_ui", %{"name" => name}, socket) do
    if System.get_env("USE_MOCK_DATA") == "true" do
      envs = Enum.reject(socket.assigns.environments, &(&1.name == name))
      {:noreply,
       socket
       |> assign(:environments, envs)
       |> put_flash(:info, "Environment '#{name}' was deleted.")}
    else
      case ExGoCD.Environments.get_environment_by_name(name) do
        nil ->
          {:noreply, put_flash(socket, :error, "Environment not found.")}
        env ->
          {:ok, _} = ExGoCD.Environments.delete_environment(env)
          envs = fetch_environments_ui()
          {:noreply,
           socket
           |> assign(:environments, envs)
           |> put_flash(:info, "Environment '#{name}' was deleted successfully.")}
      end
    end
  end

  @impl true
  def handle_event("save_environment_ui", params, socket) do
    selected_pipelines = Map.get(params, "pipelines", [])
    variables = parse_save_env_variables(Map.get(params, "variables", %{}))

    if System.get_env("USE_MOCK_DATA") == "true" do
      save_mock_environment_ui(params, selected_pipelines, variables, socket)
    else
      save_db_environment_ui(params, selected_pipelines, variables, socket)
    end
  end

  @impl true
  def handle_event("cleanup_stuck_jobs", _, socket) do
    count = Pipelines.cleanup_stuck_jobs()
    Events.admin_cleanup_stuck_jobs(socket.assigns.current_user.username, count)
    {:noreply, socket |> put_flash(:info, "Cancelled #{count} stuck jobs.")}
  end

  @impl true
  def handle_event("reset_pipeline", %{"name" => name}, socket) do
    case Pipelines.reset_pipeline(name) do
      {:ok, _} ->
        Events.admin_reset_pipeline(socket.assigns.current_user.username, name)
        {:noreply, socket |> put_flash(:info, "Pipeline #{name} reset.")}
      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Pipeline #{name} not found.")}
    end
  end

  # --- Audit Log handlers ---

  @impl true
  def handle_event("search_audit_log", %{"actor" => actor, "action" => action, "resource_type" => resource_type, "resource_name" => resource_name, "date_from" => date_from, "date_to" => date_to}, socket) do
    filters = build_audit_filters(actor, action, resource_type, resource_name, date_from, date_to)
    {:noreply, load_audit_log(socket, filters)}
  end

  @impl true
  def handle_event("reset_audit_log_filters", _params, socket) do
    {:noreply, load_audit_log(socket, %{})}
  end

  defp load_audit_log(socket, filters) do
    entries =
      if use_mock?() do
        mock = ExGoCD.MockData.audit_log_entries()
        if filters == %{} do
          mock
        else
          Enum.filter(mock, fn e ->
            (is_nil(filters[:actor]) || filters[:actor] == "" || String.contains?(String.downcase(e.actor), String.downcase(filters[:actor]))) &&
            (is_nil(filters[:action]) || filters[:action] == "" || String.contains?(e.action, filters[:action])) &&
            (is_nil(filters[:resource_type]) || filters[:resource_type] == "" || String.contains?(e.resource_type, filters[:resource_type]))
          end)
        end
      else
        AuditLog.search(filters)
      end

    socket
    |> assign(:audit_log_entries, entries)
    |> assign(:audit_log_filters, filters)
  end

  defp build_audit_filters(actor, action, resource_type, resource_name, date_from_str, date_to_str) do
    %{}
    |> put_if_present(:actor, actor)
    |> put_if_present(:action, action)
    |> put_if_present(:resource_type, resource_type)
    |> put_if_present(:resource_name, resource_name)
    |> put_if_present(:date_from, parse_date(date_from_str))
    |> put_if_present(:date_to, parse_date(date_to_str))
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, ""), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  # --- Moved handlers & helpers ---

  @impl true
  def handle_info(:backup_complete, socket) do
    backup_path = "/var/lib/go-server/db/backups/backup_config_xml_#{System.unique_integer([:positive])}.zip"
    {:noreply,
     socket
     |> assign(:backup_status, "Completed")
     |> assign(:backup_message, "Backup saved to: #{backup_path} successfully at #{DateTime.utc_now() |> DateTime.to_string()}")
     |> assign(:flash_info, "Database config backup completed successfully.")}
  end

  defp maybe_delete_group_pipelines(nil), do: :noop

  defp maybe_delete_group_pipelines(group) do
    Enum.each(group.pipelines, fn pipe -> Pipelines.delete_pipeline_by_name(pipe.name) end)
  end

  defp save_new_user(socket, params, roles) do
    attrs = %{
      "username" => params["username"],
      "display_name" => params["display_name"],
      "roles" => roles,
      "status" => "Active"
    }

    case Accounts.create_user(attrs) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(:show_user_modal, false)
         |> assign(:flash_info, "User created successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :user_errors, format_changeset_errors(changeset))}
    end
  end

  defp save_user_roles(socket, params, roles) do
    user = socket.assigns.selected_user
    attrs = %{"display_name" => params["display_name"], "roles" => roles}

    case Accounts.update_user(user, attrs) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(:show_user_modal, false)
         |> assign(:flash_info, "User configuration updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :user_errors, format_changeset_errors(changeset))}
    end
  end

  defp filter_group_pipelines(group, cleaned) do
    %{group | pipelines: Enum.filter(group.pipelines, &pipeline_name_match?(&1, cleaned))}
  end

  defp pipeline_name_match?(pipe, cleaned) do
    String.contains?(String.downcase(pipe.name), String.downcase(cleaned))
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        to_string(opts[String.to_existing_atom(key)])
      end)
    end)
  end

  defp map_variables_for_modal(vars) do
    Enum.map(vars || [], fn var ->
      %{
        "name" => var["name"] || var[:name],
        "value" => var["value"] || var[:value] || var["encrypted_value"] || var[:encrypted_value],
        "secure" => var["secure"] || var[:secure] || false
      }
    end)
  end

  defp parse_save_env_variables(vars_params) do
    vars_params
    |> Map.values()
    |> Enum.reject(fn var -> String.trim(var["name"]) == "" end)
    |> Enum.map(fn var ->
      sec = var["secure"] == "true"
      base = %{
        "name" => var["name"],
        "secure" => sec
      }
      if sec do
        Map.put(base, "encrypted_value", Base.encode64(var["value"]))
      else
        Map.put(base, "value", var["value"])
      end
    end)
  end

  defp save_mock_environment_ui(params, selected_pipelines, variables, socket) do
    name = params["name"] || socket.assigns.env_form_name
    new_env = %{
      id: socket.assigns.selected_env && socket.assigns.selected_env.id || System.unique_integer([:positive]),
      name: name,
      pipelines: selected_pipelines,
      agents: 0,
      environment_variables: variables
    }
    envs =
      if socket.assigns.env_modal_type == :create do
        socket.assigns.environments ++ [new_env]
      else
        map_update_envs(socket.assigns.environments, socket.assigns.env_form_name, new_env)
      end

    {:noreply,
     socket
     |> assign(:environments, envs)
     |> assign(:show_env_modal, false)
     |> put_flash(:info, "Environment saved successfully (Mock).")}
  end

  defp map_update_envs(envs, form_name, new_env) do
    Enum.map(envs, fn e ->
      if e.name == form_name, do: new_env, else: e
    end)
  end

  defp save_db_environment_ui(params, selected_pipelines, variables, socket) do
    res =
      if socket.assigns.env_modal_type == :create do
        ExGoCD.Environments.create_environment(%{
          "name" => params["name"],
          "pipelines" => selected_pipelines,
          "environment_variables" => variables
        })
      else
        ExGoCD.Environments.update_environment(socket.assigns.selected_env, %{
          "pipelines" => selected_pipelines,
          "environment_variables" => variables
        })
      end

    case res do
      {:ok, _env} ->
        envs = fetch_environments_ui()
        {:noreply,
         socket
         |> assign(:environments, envs)
         |> assign(:show_env_modal, false)
         |> put_flash(:info, "Environment saved successfully.")}

      {:error, changeset} ->
        error_msg =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{v}" end)

        {:noreply, put_flash(socket, :error, "Failed to save: #{error_msg}")}
    end
  end

  # --- UI Environments Helpers ---

  defp load_available_pipelines(env_id \\ nil) do
    all_pipelines = ExGoCD.Pipelines.list_pipelines()

    assigned_pipeline_ids =
      if System.get_env("USE_MOCK_DATA") == "true" do
        []
      else
        ExGoCD.Environments.list_environments()
        |> Enum.reject(fn e -> env_id && e.id == env_id end)
        |> Enum.flat_map(& &1.pipelines)
        |> Enum.map(& &1.id)
      end

    Enum.filter(all_pipelines, fn p ->
      p.id not in assigned_pipeline_ids
    end)
  end

  defp fetch_environments_ui do
    if System.get_env("USE_MOCK_DATA") == "true" do
      [
        %{id: 1, name: "staging", pipelines: ["deploy-staging", "demo-app"], agents: 2},
        %{id: 2, name: "production", pipelines: ["deploy-production"], agents: 4}
      ]
    else
      ExGoCD.Environments.list_environments()
      |> Enum.map(fn env ->
        agents_count = length(ExGoCD.Agents.list_agents_in_environment(env.name))
        pipe_names = Enum.map(env.pipelines, & &1.name)

        %{
          id: env.id,
          name: env.name,
          pipelines: pipe_names,
          agents: agents_count,
          environment_variables: env.environment_variables || []
        }
      end)
    end
  end

  defp env_modal_layer(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
      <div class="bg-white rounded border border-[#d6e0e2] shadow-xl w-full max-w-lg overflow-hidden">
        <div class="bg-[#e7eef0] border-b border-[#d6e0e2] px-5 py-3 flex justify-between items-center">
          <h3 class="text-xs font-bold uppercase tracking-wider text-slate-700">
            <%= if @type == :create, do: "Create New Environment", else: "Configure Environment: #{@name}" %>
          </h3>
          <button type="button" phx-click="close_env_modal" class="text-slate-400 hover:text-slate-600 border-0 bg-transparent cursor-pointer">
            <i class="fa fa-times"></i>
          </button>
        </div>

        <form phx-submit="save_environment_ui" class="p-6 space-y-4 text-xs max-h-[80vh] overflow-y-auto">
          <%= if @type == :create do %>
            <div>
              <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Environment Name</label>
              <input type="text" name="name" value={@name} required placeholder="e.g. production"
                     class="w-full px-3 py-2 rounded bg-white border border-[#d6e0e2] text-xs text-[#333] focus:outline-none focus:border-[#943a9e]" />
            </div>
          <% end %>

          <div>
            <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Assign Pipelines</label>
            <%= if Enum.empty?(@available_pipelines) do %>
              <p class="text-slate-400 italic">No unassigned pipelines available.</p>
            <% else %>
              <div class="grid grid-cols-2 gap-2 mt-2 bg-slate-50 p-4 rounded border border-[#e9edef] max-h-40 overflow-y-auto">
                <%= for pipe <- @available_pipelines do %>
                  <label class="flex items-center gap-2.5 font-medium text-slate-700 cursor-pointer">
                    <input type="checkbox" name="pipelines[]" value={pipe.name} checked={pipe.name in @selected_pipelines}
                           class="rounded border-[#d6e0e2] text-[#943a9e] focus:ring-[#943a9e]" />
                    <span>{pipe.name}</span>
                  </label>
                <% end %>
              </div>
            <% end %>
          </div>

          <div>
            <div class="flex justify-between items-center mb-2">
              <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider">Environment Variables</label>
              <button type="button" phx-click="add_env_var_row" class="text-[#943a9e] hover:text-purple-800 font-bold text-[10px] uppercase border-0 bg-transparent cursor-pointer">
                <i class="fa fa-plus mr-1"></i> Add Variable
              </button>
            </div>

            <div class="space-y-2 max-h-48 overflow-y-auto">
              <%= for {var, idx} <- Enum.with_index(@variables) do %>
                <div class="flex gap-2 items-center">
                  <input type="text" name={"variables[#{idx}][name]"} value={var["name"] || var[:name]} required placeholder="Name"
                         class="w-1/3 px-2 py-1 rounded border border-[#d6e0e2] text-xs" />

                  <input type={if(var["secure"] || var[:secure], do: "password", else: "text")}
                         name={"variables[#{idx}][value]"} value={var["value"] || var[:value] || var["encrypted_value"] || var[:encrypted_value]} required placeholder="Value"
                         class="flex-grow px-2 py-1 rounded border border-[#d6e0e2] text-xs" />

                  <label class="flex items-center gap-1 cursor-pointer">
                    <input type="checkbox" name={"variables[#{idx}][secure]"} value="true" checked={var["secure"] || var[:secure]}
                           phx-click="toggle_var_secure" phx-value-index={idx}
                           class="rounded border-[#d6e0e2] text-[#943a9e] focus:ring-[#943a9e]" />
                    <span class="text-[9px] uppercase font-bold text-slate-400">Secure</span>
                  </label>

                  <button type="button" phx-click="remove_env_var_row" phx-value-index={idx} class="text-rose-500 hover:text-rose-700 p-1 border-0 bg-transparent cursor-pointer">
                    <i class="fa fa-trash-can"></i>
                  </button>
                </div>
              <% end %>
              <%= if Enum.empty?(@variables) do %>
                <p class="text-slate-400 italic">No environment variables configured.</p>
              <% end %>
            </div>
          </div>

          <div class="flex justify-end gap-3 pt-4 border-t border-[#e9edef]">
            <button type="submit" class="px-4 py-2 bg-[#943a9e] hover:bg-purple-700 text-white font-bold rounded shadow-sm border-0 cursor-pointer">
              Save Environment
            </button>
            <button type="button" phx-click="close_env_modal" class="px-4 py-2 bg-white border border-slate-350 text-slate-700 rounded hover:bg-slate-50 font-semibold cursor-pointer">
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp audit_log_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Search / Filter Panel -->
      <div class="bg-white rounded border border-[#d6e0e2] p-5 shadow-sm">
        <form phx-change="search_audit_log" class="space-y-4">
          <h3 class="text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">
            <i class="fa fa-filter mr-1.5 text-[#943a9e]"></i>Filter Audit Events
          </h3>

          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div>
              <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1.5">Actor</label>
              <input type="text" name="actor" value={@filters[:actor] || ""} placeholder="e.g. admin"
                     class="w-full px-3 py-2 rounded border border-[#d6e0e2] text-xs text-slate-700 focus:outline-none focus:border-[#943a9e]" />
            </div>
            <div>
              <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1.5">Action</label>
              <input type="text" name="action" value={@filters[:action] || ""} placeholder="e.g. pipeline.trigger"
                     class="w-full px-3 py-2 rounded border border-[#d6e0e2] text-xs text-slate-700 focus:outline-none focus:border-[#943a9e]" />
            </div>
            <div>
              <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1.5">Resource Type</label>
              <input type="text" name="resource_type" value={@filters[:resource_type] || ""} placeholder="e.g. pipeline"
                     class="w-full px-3 py-2 rounded border border-[#d6e0e2] text-xs text-slate-700 focus:outline-none focus:border-[#943a9e]" />
            </div>
            <div>
              <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1.5">Resource Name</label>
              <input type="text" name="resource_name" value={@filters[:resource_name] || ""} placeholder="e.g. build-linux"
                     class="w-full px-3 py-2 rounded border border-[#d6e0e2] text-xs text-slate-700 focus:outline-none focus:border-[#943a9e]" />
            </div>
            <div>
              <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1.5">From Date</label>
              <input type="date" name="date_from" value={@filters[:date_from] || ""}
                     class="w-full px-3 py-2 rounded border border-[#d6e0e2] text-xs text-slate-700 focus:outline-none focus:border-[#943a9e]" />
            </div>
            <div>
              <label class="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1.5">To Date</label>
              <input type="date" name="date_to" value={@filters[:date_to] || ""}
                     class="w-full px-3 py-2 rounded border border-[#d6e0e2] text-xs text-slate-700 focus:outline-none focus:border-[#943a9e]" />
            </div>
          </div>

          <div class="flex justify-end">
            <button type="button" phx-click="reset_audit_log_filters"
                    class="px-4 py-2 rounded bg-white border border-[#d6e0e2] text-xs font-semibold text-slate-600 hover:bg-slate-50 transition-all">
              <i class="fa fa-undo mr-1"></i> Reset Filters
            </button>
          </div>
        </form>
      </div>

      <!-- Results Table -->
      <div class="bg-white rounded border border-[#d6e0e2] overflow-hidden shadow-sm">
        <div class="overflow-x-auto">
          <table class="w-full text-left text-xs text-slate-600 font-sans">
            <thead class="bg-[#e7eef0] text-[10px] font-bold text-slate-500 uppercase border-b border-[#d6e0e2]">
              <tr>
                <th class="px-5 py-3.5 w-44">Timestamp</th>
                <th class="px-5 py-3.5">Actor</th>
                <th class="px-5 py-3.5">Action</th>
                <th class="px-5 py-3.5">Resource</th>
                <th class="px-5 py-3.5">Details</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-[#e9edef] bg-white">
              <%= if Enum.empty?(@entries) do %>
                <tr>
                  <td colspan="5" class="px-5 py-12 text-center text-slate-400 italic text-xs">
                    No audit log entries found.
                  </td>
                </tr>
              <% else %>
                <%= for entry <- @entries do %>
                  <tr class="hover:bg-slate-50/50">
                    <td class="px-5 py-3 font-mono text-[11px] text-slate-500 whitespace-nowrap">
                      {format_audit_timestamp(entry.inserted_at)}
                    </td>
                    <td class="px-5 py-3">
                      <span class="inline-flex items-center gap-1.5 font-semibold text-slate-700">
                        <i class="fa fa-user text-[10px] text-slate-400"></i>
                        {entry.actor}
                      </span>
                    </td>
                    <td class="px-5 py-3">
                      <span class="bg-slate-100 text-slate-600 px-2 py-0.5 rounded text-[10px] font-mono font-semibold">
                        {entry.action}
                      </span>
                    </td>
                    <td class="px-5 py-3">
                      <%= if entry.resource_type do %>
                        <span class="text-slate-600">
                          {entry.resource_type}<%= if entry.resource_name, do: " / #{entry.resource_name}" %>
                        </span>
                      <% else %>
                        <span class="text-slate-400 italic">—</span>
                      <% end %>
                    </td>
                    <td class="px-5 py-3 max-w-xs">
                      <%= if entry.details && map_size(entry.details) > 0 do %>
                        <code class="text-[11px] text-slate-500 bg-slate-50 px-2 py-0.5 rounded block truncate" title={Jason.encode_to_iodata!(entry.details) |> IO.iodata_to_binary()}>
                          {Jason.encode_to_iodata!(entry.details) |> IO.iodata_to_binary()}
                        </code>
                      <% else %>
                        <span class="text-slate-400 italic">—</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>

        <div class="bg-[#f8fafb] border-t border-[#e9edef] px-5 py-2.5 text-[10px] text-slate-400 flex justify-between items-center">
          <span>Showing {length(@entries)} of up to 200 recent entries</span>
          <span>All times UTC</span>
        </div>
      </div>
    </div>
    """
  end

  defp format_audit_timestamp(nil), do: "—"
  defp format_audit_timestamp(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end
end
