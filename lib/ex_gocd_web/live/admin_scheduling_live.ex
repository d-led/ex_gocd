defmodule ExGoCDWeb.AdminSchedulingLive do
  @moduledoc """
  Admin live view for diagnosing scheduling state.

  Shows:
  - Pending jobs in the scheduler queue (in-memory + DB)
  - All agents with their state, resources, and environments
  - Match analysis: for each pending job, which agents can take it
  - Why a job is stuck (no matching agent, agents busy, etc.)

  Auto-refreshes via PubSub subscriptions to scheduler and agent updates.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.{Agents, Scheduler, AuditLog}
  alias ExGoCD.Pipelines.JobInstance
  alias ExGoCD.Repo

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    unless socket.assigns[:is_user_admin] do
      {:ok,
       socket
       |> put_flash(:error, "You do not have administration permissions.")
       |> redirect(to: "/")}
    else
      if connected?(socket) do
        Scheduler.subscribe()
        Agents.subscribe()
      end

      {:ok,
       socket
       |> assign(:page_title, "GoCD Administration - Scheduling")
       |> assign(:current_path, "/admin/scheduling")
       |> refresh_all()}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:pending_count, _count}, socket) do
    {:noreply, refresh_all(socket)}
  end

  def handle_info(
        {event, _agent},
        socket
      )
      when event in [
             :agent_registered,
             :agent_updated,
             :agent_enabled,
             :agent_disabled,
             :agent_deleted
           ] do
    {:noreply, refresh_all(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, refresh_all(socket)}
  end

  def handle_event("show_error", %{"index" => idx}, socket) do
    errors = socket.assigns.recent_errors
    {i, ""} = Integer.parse(idx)
    error = Enum.at(errors, i)
    {:noreply, assign(socket, :selected_error, error)}
  end

  def handle_event("close_error", _, socket) do
    {:noreply, assign(socket, :selected_error, nil)}
  end

  # -- private ----------------------------------------------------------------

  defp refresh_all(socket) do
    socket
    |> assign(:queue_state, Scheduler.get_queue_state())
    |> assign(:agents, fetch_agents())
    |> assign(:now, DateTime.utc_now())
    |> assign(:active_jobs, fetch_active_db_jobs())
    |> assign(:recent_errors, fetch_recent_errors())      |> assign(:selected_error, nil)    |> assign_match_analysis()
  end

  defp fetch_agents do
    Agents.list_agents()
    |> Enum.reject(&(&1.deleted == true))
    |> Enum.sort_by(&{agent_sort_priority(&1), &1.hostname})
  end

  defp fetch_recent_errors do
    AuditLog.recent(100)
    |> Enum.filter(fn entry ->
      entry.action in ["server.crash", "poller_error", "material_error"] or
        String.contains?(entry.action || "", "error") or
        String.contains?(entry.action || "", "fail")
    end)
    |> Enum.take(10)
    |> Enum.map(fn entry ->
      _detail = entry.details || %{}
      %{
        time: entry.inserted_at,
        action: entry.action,
        message: format_error_message(entry),
        resource: entry.resource_name
      }
    end)
  end

  defp format_error_message(entry) do
    detail = entry.details || %{}
    payload = detail["payload"] || detail[:payload] || %{}

    payload["exception.message"] ||
      payload[:exception] ||
      detail["error"] ||
      detail["message"] ||
      format_map(detail)
  end

  defp format_map(map) when is_map(map) and map_size(map) > 0 do
    map
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
    |> then(&String.slice(&1, 0, 200))
  end

  defp format_map(_), do: ""

  # Idle first, Building second, then everything else, then disabled last
  defp agent_sort_priority(agent) do
    cond do
      agent.disabled -> 3
      agent.state == "Idle" -> 0
      agent.state == "Building" -> 1
      true -> 2
    end
  end

  defp fetch_scheduled_db_jobs do
    JobInstance
    |> where([j], j.state == "Scheduled")
    |> order_by(asc: :id)
    |> preload([:job, stage_instance: [pipeline_instance: :pipeline]])
    |> Repo.all()
    |> Enum.map(&map_job_instance/1)
  end

  defp fetch_active_db_jobs do
    JobInstance
    |> where([j], j.state in ["Assigned", "Building", "Completing"])
    |> order_by(asc: :id)
    |> preload([:job, stage_instance: [pipeline_instance: :pipeline]])
    |> Repo.all()
    |> Enum.map(&map_job_instance/1)
  end

  defp map_job_instance(ji) do
    stage_instance = ji.stage_instance
    pipeline_instance = stage_instance.pipeline_instance
    pipeline = pipeline_instance.pipeline
    job_config = ji.job

    resources = (job_config && job_config.resources) || []
    envs = ExGoCD.Scheduler.get_pipeline_environments(pipeline.name)

    %{
      job_instance_id: ji.id,
      pipeline_name: pipeline.name,
      pipeline_counter: pipeline_instance.counter,
      stage_name: stage_instance.name,
      stage_counter: stage_instance.counter,
      job_name: ji.name,
      resources: resources,
      environments: envs,
      agent_uuid: ji.agent_uuid,
      state: ji.state,
      scheduled_at: ji.scheduled_at,
      inserted_at: ji.inserted_at
    }
  end

  defp assign_match_analysis(socket) do
    agents = socket.assigns.agents
    queue_state = socket.assigns.queue_state

    db_jobs = fetch_scheduled_db_jobs()
    all_jobs = (queue_state.in_memory_jobs || []) ++ db_jobs

    job_matches =
      Enum.map(all_jobs, fn job ->
        matching = matching_agents(job, agents)

        %{
          job: job,
          matching_agents: matching,
          stuck_reason: stuck_reason(job, matching, agents)
        }
      end)
      |> Enum.sort_by(fn m ->
        # Stuck jobs first, then by pipeline name + counter for stable order
        {!is_nil(m.stuck_reason), job_field(m.job, :pipeline_name) || "", job_field(m.job, :pipeline_counter) || 0}
      end)

    assign(socket, :job_matches, job_matches)
  end

  defp matching_agents(job, agents) do
    job_resources = (job[:resources] || job.resources || []) |> Enum.map(&String.downcase/1)
    job_envs = (job[:environments] || job.environments || []) |> Enum.map(&String.downcase/1)

    agents
    |> Enum.filter(fn agent ->
      agent_resources = (agent.resources || []) |> Enum.map(&String.downcase/1) |> MapSet.new()
      agent_envs = (agent.environments || []) |> Enum.map(&String.downcase/1) |> MapSet.new()

      # If job is pinned to a specific agent
      pinned = job[:agent_uuid] || job.agent_uuid

      if is_binary(pinned) and pinned != "" do
        agent.uuid == pinned
      else
        resources_match?(job_resources, agent_resources) and
          envs_match?(job_envs, agent_envs)
      end
    end)
  end

  defp resources_match?([], _agent_resources), do: true

  defp resources_match?(job_resources, agent_resources) do
    Enum.all?(job_resources, &MapSet.member?(agent_resources, &1))
  end

  defp envs_match?([], agent_envs) do
    MapSet.equal?(agent_envs, MapSet.new())
  end

  defp envs_match?(job_envs, agent_envs) do
    not Enum.empty?(job_envs) and
      Enum.any?(job_envs, &MapSet.member?(agent_envs, &1))
  end

  defp stuck_reason(job, matching, all_agents) do
    pinned = job[:agent_uuid] || job.agent_uuid

    cond do
      is_binary(pinned) and pinned != "" ->
        pinned_agent_reason(pinned, all_agents)

      Enum.empty?(matching) ->
        no_matching_agent_reason(job, all_agents)

      Enum.all?(matching, &(&1.state != "Idle")) ->
        busy_names = matching |> Enum.map(& &1.hostname) |> Enum.join(", ")
        "All matching agents are busy: #{busy_names}"

      Enum.all?(matching, &(&1.disabled == true)) ->
        "All matching agents are disabled"

      true ->
        nil
    end
  end

  defp pinned_agent_reason(pinned, all_agents) do
    case Enum.find(all_agents, &(&1.uuid == pinned)) do
      nil -> "Pinned to agent #{String.slice(pinned, 0, 8)}… which is not registered"
      %{disabled: true, hostname: h} -> "Pinned to agent #{h} which is disabled"
      %{state: "LostContact", hostname: h} -> "Pinned to agent #{h} which has lost contact"
      %{state: "Building", hostname: h} -> "Pinned to agent #{h} which is currently building"
      _ -> nil
    end
  end

  defp no_matching_agent_reason(job, all_agents) do
    job_resources = job[:resources] || job.resources || []
    job_envs = job[:environments] || job.environments || []

    reasons =
      [
        resource_reason(job_resources, all_agents),
        environment_reason(job_envs, all_agents),
        unconfigured_reason(job_resources, job_envs)
      ]
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(reasons), do: nil, else: Enum.join(reasons, "; ")
  end

  defp resource_reason([], _all_agents), do: nil

  defp resource_reason(job_resources, all_agents) do
    if Enum.any?(all_agents, &agent_has_all_resources?(&1, job_resources)),
      do: nil,
      else: "No agent has all required resources: #{Enum.join(job_resources, ", ")}"
  end

  defp environment_reason([], _all_agents), do: nil

  defp environment_reason(job_envs, all_agents) do
    if Enum.any?(all_agents, &agent_in_matching_env?(&1, job_envs)),
      do: nil,
      else: "No agent is in a matching environment: #{Enum.join(job_envs, ", ")}"
  end

  defp unconfigured_reason([], []), do: "No agents are registered and enabled"
  defp unconfigured_reason(_, _), do: nil

  defp agent_has_all_resources?(agent, job_resources) do
    agent_resources = (agent.resources || []) |> Enum.map(&String.downcase/1) |> MapSet.new()

    Enum.all?(job_resources, fn r ->
      MapSet.member?(agent_resources, String.downcase(r))
    end)
  end

  defp agent_in_matching_env?(agent, job_envs) do
    agent_envs = downcase_set(agent.environments || [])
    job_envs_lower = Enum.map(job_envs, &String.downcase/1)

    if MapSet.equal?(agent_envs, MapSet.new()) do
      Enum.empty?(job_envs_lower)
    else
      Enum.any?(job_envs_lower, &MapSet.member?(agent_envs, &1))
    end
  end

  defp downcase_set(list), do: list |> Enum.map(&String.downcase/1) |> MapSet.new()

  # -- helpers used in template -----------------------------------------------

  defp job_label(job) do
    p = job_field(job, :pipeline_name) || job_field(job, :pipeline) || "?"
    c = job_field(job, :pipeline_counter) || 0
    s = job_field(job, :stage_name) || job_field(job, :stage) || "?"
    sc = job_field(job, :stage_counter) || 0
    jn = job_field(job, :job_name) || job_field(job, :job) || "?"

    "#{p}/#{c}/#{s}/#{sc}/#{jn}"
  end

  defp job_detail_path(job) do
    p = job_field(job, :pipeline_name) || "?"
    c = job_field(job, :pipeline_counter) || 0
    s = job_field(job, :stage_name) || "?"
    sc = job_field(job, :stage_counter) || 0
    jn = job_field(job, :job_name) || "?"

    ~p"/go/tab/build/detail/#{p}/#{c}/#{s}/#{sc}/#{jn}"
  end

  defp job_vsm_path(job) do
    p = job_field(job, :pipeline_name) || "?"
    c = job_field(job, :pipeline_counter) || 0
    ~p"/pipelines/value_stream_map/#{p}/#{c}"
  end

  defp job_activity_path(job) do
    p = job_field(job, :pipeline_name) || "?"
    ~p"/pipeline/activity/#{p}"
  end

  defp agent_job_history_path(agent_uuid) when is_binary(agent_uuid) and agent_uuid != "",
    do: ~p"/agents/#{agent_uuid}/job_run_history"

  defp agent_job_history_path(_), do: nil

  defp job_field(job, key) do
    # Try Access first (works for maps with string keys and structs with atom keys)
    case Access.fetch(job, key) do
      {:ok, val} when not is_nil(val) -> val
      _ -> nil
    end
  end

  defp job_source(job) do
    if job_field(job, :job_instance_id), do: "DB", else: "Memory"
  end

  defp agent_status_class(agent) do
    cond do
      agent.disabled -> "text-gray-400"
      agent.state == "Idle" -> "text-green-600"
      agent.state == "Building" -> "text-blue-600"
      agent.state == "LostContact" -> "text-red-500"
      true -> "text-gray-500"
    end
  end

  defp agent_state_label(agent) do
    if agent.disabled, do: "Disabled", else: agent.state || "Unknown"
  end

  defp format_duration(inserted_at, now) do
    seconds = DateTime.diff(now, inserted_at)

    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end

  defp count_idle(agents) do
    agents |> Enum.count(&(&1.state == "Idle" and &1.disabled != true))
  end

  defp count_building(agents) do
    agents |> Enum.count(&(&1.state == "Building"))
  end

  defp count_lost(agents) do
    agents |> Enum.count(&(&1.state == "LostContact"))
  end

  defp count_disabled(agents) do
    agents |> Enum.count(&(&1.disabled == true))
  end

  defp pending_color(0), do: "text-green-600"
  defp pending_color(_), do: "text-amber-600"

  defp stuck_color(0), do: "text-green-600"
  defp stuck_color(_), do: "text-red-600"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-scheduling min-h-screen bg-[#f4f8f9] text-[#333] font-sans pb-12">
      <.error_modal :if={@selected_error} error={@selected_error} />
      <!-- Header -->
      <div class="bg-white border-b border-[#e9edef] px-6 py-4 flex justify-between items-center">
        <h1 class="text-xl font-semibold text-[#333] uppercase tracking-wide">
          Scheduling Diagnostics
        </h1>
        <button
          phx-click="refresh"
          class="px-4 py-2 text-sm bg-[#f4f8f9] border border-[#d6e0e2] rounded hover:bg-[#e9edef] transition-colors"
        >
          ↻ Refresh
        </button>
      </div>

      <div class="px-6 py-4 space-y-6">
        <!-- Summary Cards -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <!-- Job Summary Card -->
          <div class="bg-white border border-[#e9edef] rounded p-4">
            <p class="text-xs font-bold text-slate-500 uppercase tracking-wide mb-3">Job Summary</p>
            <div class="flex items-center gap-6">
              <div class="flex items-baseline gap-2">
                <span class={"text-3xl font-bold " <> pending_color(@queue_state.pending_count)}>
                  {@queue_state.pending_count}
                </span>
                <span class="text-xs text-slate-400">pending</span>
              </div>
              <div class="flex items-baseline gap-2">
                <span class={"text-3xl font-bold " <> stuck_color(stuck_count(@job_matches))}>
                  {stuck_count(@job_matches)}
                </span>
                <span class="text-xs text-slate-400">stuck</span>
              </div>
            </div>
            <p class="text-xs text-slate-400 mt-2">
              {@queue_state.in_memory_count} in memory &middot; {@queue_state.db_count} in DB
            </p>
          </div>

          <!-- Agent Summary Card -->
          <div class="bg-white border border-[#e9edef] rounded p-4">
            <p class="text-xs font-bold text-slate-500 uppercase tracking-wide mb-3">Agent Summary</p>
            <div class="flex items-center gap-6">
              <div class="flex items-baseline gap-2">
                <span class="text-3xl font-bold text-slate-700">
                  {length(@agents)}
                </span>
                <span class="text-xs text-slate-400">total</span>
              </div>
              <div class="flex flex-wrap gap-3">
                <div class="flex items-baseline gap-1">
                  <span class="text-lg font-bold text-green-600">{count_idle(@agents)}</span>
                  <span class="text-[10px] text-slate-400">idle</span>
                </div>
                <div class="flex items-baseline gap-1">
                  <span class="text-lg font-bold text-blue-600">{count_building(@agents)}</span>
                  <span class="text-[10px] text-slate-400">building</span>
                </div>
                <div class="flex items-baseline gap-1">
                  <span class="text-lg font-bold text-red-500">{count_lost(@agents)}</span>
                  <span class="text-[10px] text-slate-400">lost</span>
                </div>
                <div class="flex items-baseline gap-1">
                  <span class="text-lg font-bold text-gray-400">{count_disabled(@agents)}</span>
                  <span class="text-[10px] text-slate-400">disabled</span>
                </div>
              </div>
            </div>
          </div>
        </div>

    <!-- Pending Jobs Table -->
        <div class="bg-white border border-[#e9edef] rounded">
          <div class="px-4 py-3 border-b border-[#e9edef]">
            <h2 class="text-sm font-bold text-slate-700 uppercase tracking-wide">
              Pending Jobs ({length(@job_matches)})
            </h2>
          </div>

          <%= if Enum.empty?(@job_matches) do %>
            <div class="p-8 text-center text-slate-400">
              No pending jobs. The queue is empty.
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-[#f4f8f9] text-left text-xs font-bold text-slate-500 uppercase tracking-wide">
                  <tr>
                    <th class="px-4 py-2">Job</th>
                    <th class="px-4 py-2">Source</th>
                    <th class="px-4 py-2">Resources</th>
                    <th class="px-4 py-2">Environments</th>
                    <th class="px-4 py-2">Waiting</th>
                    <th class="px-4 py-2">Matching Agents</th>
                    <th class="px-4 py-2">Stuck Reason</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for match <- @job_matches do %>
                    <tr class={"border-t border-[#e9edef] #{if match.stuck_reason, do: "bg-red-50", else: ""}"}>
                      <td class="px-4 py-3 font-mono text-xs">
                        <.link navigate={job_detail_path(match.job)} class="text-[#943a9e] hover:underline">
                          {job_label(match.job)}
                        </.link>
                        <div class="flex items-center gap-2 mt-0.5">
                          <.link navigate={job_activity_path(match.job)} class="text-[10px] text-slate-400 hover:text-slate-600">
                            activity
                          </.link>
                          <span class="text-slate-300">·</span>
                          <.link navigate={job_vsm_path(match.job)} class="text-[10px] text-slate-400 hover:text-slate-600">
                            VSM
                          </.link>
                        </div>
                      </td>
                      <td class="px-4 py-3">
                        <span class="text-xs bg-slate-100 text-slate-600 px-2 py-0.5 rounded">
                          {job_source(match.job)}
                        </span>
                      </td>
                      <td class="px-4 py-3">
                        <%= if Enum.empty?(match.job[:resources] || match.job.resources || []) do %>
                          <span class="text-slate-400 text-xs">—</span>
                        <% else %>
                          <div class="flex flex-wrap gap-1">
                            <%= for r <- (match.job[:resources] || match.job.resources || []) do %>
                              <span class="text-xs bg-blue-50 text-blue-700 px-1.5 py-0.5 rounded">
                                {r}
                              </span>
                            <% end %>
                          </div>
                        <% end %>
                      </td>
                      <td class="px-4 py-3">
                        <%= if Enum.empty?(match.job[:environments] || match.job.environments || []) do %>
                          <span class="text-slate-400 text-xs">—</span>
                        <% else %>
                          <div class="flex flex-wrap gap-1">
                            <%= for e <- (match.job[:environments] || match.job.environments || []) do %>
                              <span class="text-xs bg-purple-50 text-purple-700 px-1.5 py-0.5 rounded">
                                {e}
                              </span>
                            <% end %>
                          </div>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-xs text-slate-500">
                        <%= if inserted = (match.job[:inserted_at] || match.job.inserted_at) do %>
                          {format_duration(inserted, @now)}
                        <% else %>
                          —
                        <% end %>
                      </td>
                      <td class="px-4 py-3">
                        <%= if Enum.empty?(match.matching_agents) do %>
                          <span class="text-red-500 text-xs font-medium">None</span>
                        <% else %>
                          <div class="flex flex-col gap-0.5">
                            <%= for agent <- match.matching_agents do %>
                              <span class={"text-xs #{agent_status_class(agent)}"}>
                                {agent.hostname}
                                <span class="text-slate-400">({agent_state_label(agent)})</span>
                              </span>
                            <% end %>
                          </div>
                        <% end %>
                      </td>
                      <td class="px-4 py-3">
                        <%= if match.stuck_reason do %>
                          <span class="text-xs text-red-600 font-medium">{match.stuck_reason}</span>
                        <% else %>
                          <span class="text-xs text-green-600">Ready to assign</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

        <%!-- Active Jobs (Assigned / Building / Completing) --%>
        <div class="bg-white border border-[#e9edef] rounded">
          <div class="px-4 py-3 border-b border-[#e9edef]">
            <h2 class="text-sm font-bold text-slate-700 uppercase tracking-wide">
              Active Jobs ({length(@active_jobs)})
            </h2>
          </div>
          <%= if Enum.empty?(@active_jobs) do %>
            <div class="p-8 text-center text-slate-400">No active jobs.</div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-[#f4f8f9] text-left text-xs font-bold text-slate-500 uppercase tracking-wide">
                  <tr>
                    <th class="px-4 py-2">Job</th>
                    <th class="px-4 py-2">State</th>
                    <th class="px-4 py-2">Agent</th>
                    <th class="px-4 py-2">Resources</th>
                    <th class="px-4 py-2">Running</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for job <- @active_jobs do %>
                    <tr class="border-t border-[#e9edef]">
                      <td class="px-4 py-3 font-mono text-xs">
                        <.link navigate={job_detail_path(job)} class="text-[#943a9e] hover:underline">
                          {job_label(job)}
                        </.link>
                        <div class="flex items-center gap-2 mt-0.5">
                          <.link navigate={job_activity_path(job)} class="text-[10px] text-slate-400 hover:text-slate-600">
                            activity
                          </.link>
                          <span class="text-slate-300">·</span>
                          <.link navigate={job_vsm_path(job)} class="text-[10px] text-slate-400 hover:text-slate-600">
                            VSM
                          </.link>
                        </div>
                      </td>
                      <td class="px-4 py-3">
                        <span class={[
                          "text-xs px-2 py-0.5 rounded font-bold",
                          case job.state do
                            "Assigned" -> "bg-amber-50 text-amber-700"
                            "Building" -> "bg-blue-50 text-blue-700"
                            "Completing" -> "bg-purple-50 text-purple-700"
                            _ -> "bg-slate-100 text-slate-600"
                          end
                        ]}>{job.state}</span>
                      </td>
                      <td class="px-4 py-3">
                        <%= if (uuid = job.agent_uuid) && uuid != "" && agent_job_history_path(uuid) do %>
                          <.link navigate={agent_job_history_path(uuid)} class="text-xs text-slate-600 hover:text-[#943a9e] font-mono hover:underline">
                            {String.slice(uuid, 0, 8)}…
                          </.link>
                        <% else %>
                          <span class="text-slate-400 text-xs">—</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-3">
                        <%= if Enum.empty?(job.resources || []) do %>
                          <span class="text-slate-400 text-xs">—</span>
                        <% else %>
                          <div class="flex flex-wrap gap-1">
                            <%= for r <- job.resources do %>
                              <span class="text-xs bg-blue-50 text-blue-700 px-1.5 py-0.5 rounded">{r}</span>
                            <% end %>
                          </div>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-xs text-slate-500">
                        <%= if inserted = job.inserted_at do %>
                          {format_duration(inserted, @now)}
                        <% else %>
                          —
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

        <%!-- Recent Errors --%>
        <%= if not Enum.empty?(@recent_errors) do %>
          <div class="bg-white border border-red-200 rounded">
            <div class="px-4 py-3 border-b border-red-200 bg-red-50">
              <h2 class="text-sm font-bold text-red-700 uppercase tracking-wide">
                ⚠ Recent Errors ({length(@recent_errors)})
              </h2>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-red-50/50 text-left text-xs font-bold text-red-500 uppercase tracking-wide">
                  <tr>
                    <th class="px-4 py-2 w-32">Time</th>
                    <th class="px-4 py-2 w-32">Type</th>
                    <th class="px-4 py-2">Message</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {err, idx} <- Enum.with_index(@recent_errors) do %>
                    <tr class="border-t border-red-100 hover:bg-red-50 cursor-pointer"
                        phx-click="show_error" phx-value-index={idx}>
                      <td class="px-4 py-2 text-xs text-slate-500 tabular-nums whitespace-nowrap">
                        {format_duration(err.time, @now)} ago
                      </td>
                      <td class="px-4 py-2">
                        <span class="text-xs bg-red-100 text-red-700 px-1.5 py-0.5 rounded font-bold">
                          {err.action}
                        </span>
                      </td>
                      <td class="px-4 py-2 text-xs text-slate-600 font-mono max-w-md truncate">
                        {err.message || "—"}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>

    <!-- Agents Table -->
        <div class="bg-white border border-[#e9edef] rounded">
          <div class="px-4 py-3 border-b border-[#e9edef]">
            <h2 class="text-sm font-bold text-slate-700 uppercase tracking-wide">
              Agents ({length(@agents)})
            </h2>
          </div>

          <%= if Enum.empty?(@agents) do %>
            <div class="p-8 text-center text-slate-400">
              No agents registered.
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-[#f4f8f9] text-left text-xs font-bold text-slate-500 uppercase tracking-wide">
                  <tr>
                    <th class="px-4 py-2">Hostname</th>
                    <th class="px-4 py-2">State</th>
                    <th class="px-4 py-2">Resources</th>
                    <th class="px-4 py-2">Environments</th>
                    <th class="px-4 py-2">OS</th>
                    <th class="px-4 py-2">Free Space</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for agent <- @agents do %>
                    <tr class="border-t border-[#e9edef]">
                      <td class="px-4 py-3 font-mono text-xs">
                        {agent.hostname}
                        <span class="text-slate-400">({String.slice(agent.uuid, 0, 8)}…)</span>
                      </td>
                      <td class="px-4 py-3">
                        <span class={"text-xs font-medium #{agent_status_class(agent)}"}>
                          ● {agent_state_label(agent)}
                        </span>
                      </td>
                      <td class="px-4 py-3">
                        <%= if Enum.empty?(agent.resources || []) do %>
                          <span class="text-slate-400 text-xs">—</span>
                        <% else %>
                          <div class="flex flex-wrap gap-1">
                            <%= for r <- agent.resources do %>
                              <span class="text-xs bg-blue-50 text-blue-700 px-1.5 py-0.5 rounded">
                                {r}
                              </span>
                            <% end %>
                          </div>
                        <% end %>
                      </td>
                      <td class="px-4 py-3">
                        <%= if Enum.empty?(agent.environments || []) do %>
                          <span class="text-slate-400 text-xs">—</span>
                        <% else %>
                          <div class="flex flex-wrap gap-1">
                            <%= for e <- agent.environments do %>
                              <span class="text-xs bg-purple-50 text-purple-700 px-1.5 py-0.5 rounded">
                                {e}
                              </span>
                            <% end %>
                          </div>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-xs text-slate-500">
                        {agent.operating_system || "—"}
                      </td>
                      <td class="px-4 py-3 text-xs text-slate-500">
                        <%= if agent.free_space do %>
                          {format_mb(agent.free_space)}
                        <% else %>
                          —
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp stuck_count(job_matches) do
    Enum.count(job_matches, &(&1.stuck_reason != nil))
  end

  defp format_mb(bytes) when is_integer(bytes) do
    mb = div(bytes, 1_048_576)
    "#{mb} MB"
  end

  defp format_mb(_), do: "—"

  defp error_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50" phx-click="close_error">
      <div class="bg-white rounded-lg shadow-xl max-w-2xl w-full mx-4 max-h-[80vh] overflow-y-auto" phx-click-away="close_error">
        <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
          <h3 class="text-lg font-semibold text-red-700">Error Details</h3>
          <button phx-click="close_error" class="text-gray-400 hover:text-gray-600 text-xl leading-none">&times;</button>
        </div>
        <div class="px-6 py-4 space-y-3">
          <div>
            <span class="text-xs font-bold text-gray-500 uppercase">Type</span>
            <span class="ml-2 text-xs bg-red-100 text-red-700 px-1.5 py-0.5 rounded font-bold">{@error.action}</span>
          </div>
          <div>
            <span class="text-xs font-bold text-gray-500 uppercase">Time</span>
            <span class="ml-2 text-sm text-gray-700">{@error.time}</span>
          </div>
          <div>
            <span class="text-xs font-bold text-gray-500 uppercase">Resource</span>
            <span class="ml-2 text-sm text-gray-700">{@error.resource || "—"}</span>
          </div>
          <div>
            <span class="text-xs font-bold text-gray-500 uppercase">Message</span>
            <pre class="mt-1 text-sm text-gray-800 bg-gray-50 p-3 rounded border border-gray-200 whitespace-pre-wrap break-words font-mono">{@error.message}</pre>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
