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

  alias ExGoCD.{Agents, Scheduler}

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

  # -- private ----------------------------------------------------------------

  defp refresh_all(socket) do
    socket
    |> assign(:queue_state, Scheduler.get_queue_state())
    |> assign(:agents, fetch_agents())
    |> assign(:now, DateTime.utc_now())
    |> assign_match_analysis()
  end

  defp fetch_agents do
    Agents.list_agents()
    |> Enum.reject(&(&1.deleted == true))
  end

  defp assign_match_analysis(socket) do
    agents = socket.assigns.agents
    queue_state = socket.assigns.queue_state

    all_jobs = (queue_state.in_memory_jobs || []) ++ (queue_state.db_jobs || [])

    job_matches =
      Enum.map(all_jobs, fn job ->
        matching = matching_agents(job, agents)

        %{
          job: job,
          matching_agents: matching,
          stuck_reason: stuck_reason(job, matching, agents)
        }
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
        pinned_agent = Enum.find(all_agents, &(&1.uuid == pinned))

        cond do
          is_nil(pinned_agent) ->
            "Pinned to agent #{String.slice(pinned, 0, 8)}… which is not registered"

          pinned_agent.disabled == true ->
            "Pinned to agent #{pinned_agent.hostname} which is disabled"

          pinned_agent.state == "LostContact" ->
            "Pinned to agent #{pinned_agent.hostname} which has lost contact"

          pinned_agent.state == "Building" ->
            "Pinned to agent #{pinned_agent.hostname} which is currently building"

          true ->
            nil
        end

      Enum.empty?(matching) ->
        job_resources = job[:resources] || job.resources || []
        job_envs = job[:environments] || job.environments || []

        reasons = []

        reasons =
          if not Enum.empty?(job_resources) and
               not Enum.any?(all_agents, &agent_has_all_resources?(&1, job_resources)) do
            ["No agent has all required resources: #{Enum.join(job_resources, ", ")}" | reasons]
          else
            reasons
          end

        reasons =
          if not Enum.empty?(job_envs) and
               not Enum.any?(all_agents, &agent_in_matching_env?(&1, job_envs)) do
            ["No agent is in a matching environment: #{Enum.join(job_envs, ", ")}" | reasons]
          else
            reasons
          end

        reasons =
          if Enum.empty?(job_resources) and Enum.empty?(job_envs) do
            ["No agents are registered and enabled" | reasons]
          else
            reasons
          end

        if Enum.empty?(reasons), do: nil, else: Enum.join(reasons, "; ")

      Enum.all?(matching, &(&1.state != "Idle")) ->
        busy_names = matching |> Enum.map(& &1.hostname) |> Enum.join(", ")
        "All matching agents are busy: #{busy_names}"

      Enum.all?(matching, &(&1.disabled == true)) ->
        "All matching agents are disabled"

      true ->
        nil
    end
  end

  defp agent_has_all_resources?(agent, job_resources) do
    agent_resources = (agent.resources || []) |> Enum.map(&String.downcase/1) |> MapSet.new()

    Enum.all?(job_resources, fn r ->
      MapSet.member?(agent_resources, String.downcase(r))
    end)
  end

  defp agent_in_matching_env?(agent, job_envs) do
    agent_envs = (agent.environments || []) |> Enum.map(&String.downcase/1) |> MapSet.new()
    job_envs_lower = Enum.map(job_envs, &String.downcase/1)

    if MapSet.equal?(agent_envs, MapSet.new()) do
      Enum.empty?(job_envs_lower)
    else
      Enum.any?(job_envs_lower, &MapSet.member?(agent_envs, &1))
    end
  end

  # -- helpers used in template -----------------------------------------------

  defp job_label(job) do
    pipeline = job[:pipeline_name] || job[:pipeline] || job.pipeline || "?"
    counter = job[:pipeline_counter] || job.pipeline_counter || 0
    stage = job[:stage_name] || job[:stage] || job.stage || "?"
    stage_counter = job[:stage_counter] || job.stage_counter || 0
    job_name = job[:job_name] || job[:job] || job.job || "?"

    "#{pipeline}/#{counter}/#{stage}/#{stage_counter}/#{job_name}"
  end

  defp job_source(job) do
    id = job[:id] || job.id || ""

    if is_binary(id) and String.starts_with?(id, "db-"),
      do: "DB",
      else: "Memory"
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
    cond do
      agent.disabled -> "Disabled"
      true -> agent.state || "Unknown"
    end
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-scheduling min-h-screen bg-[#f4f8f9] text-[#333] font-sans pb-12">
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
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div class="bg-white border border-[#e9edef] rounded p-4">
            <p class="text-xs font-bold text-slate-500 uppercase tracking-wide">Pending Jobs</p>
            <p class={"text-2xl font-bold mt-1 #{if @queue_state.pending_count > 0, do: "text-amber-600", else: "text-green-600"}"}>
              {@queue_state.pending_count}
            </p>
            <p class="text-xs text-slate-400 mt-1">
              {@queue_state.in_memory_count} memory + {@queue_state.db_count} DB
            </p>
          </div>

          <div class="bg-white border border-[#e9edef] rounded p-4">
            <p class="text-xs font-bold text-slate-500 uppercase tracking-wide">Agents Total</p>
            <p class="text-2xl font-bold mt-1">{length(@agents)}</p>
          </div>

          <div class="bg-white border border-[#e9edef] rounded p-4">
            <p class="text-xs font-bold text-slate-500 uppercase tracking-wide">
              Idle / Building / Lost
            </p>
            <p class="text-2xl font-bold mt-1">
              <span class="text-green-600">{count_idle(@agents)}</span>
              <span class="text-slate-400 mx-1">/</span>
              <span class="text-blue-600">{count_building(@agents)}</span>
              <span class="text-slate-400 mx-1">/</span>
              <span class="text-red-500">{count_lost(@agents)}</span>
            </p>
            <p class="text-xs text-slate-400 mt-1">
              {count_disabled(@agents)} disabled
            </p>
          </div>

          <div class="bg-white border border-[#e9edef] rounded p-4">
            <p class="text-xs font-bold text-slate-500 uppercase tracking-wide">Stuck Jobs</p>
            <p class={"text-2xl font-bold mt-1 " <> if(stuck_count(@job_matches) > 0, do: "text-red-600", else: "text-green-600")}>
              {stuck_count(@job_matches)}
            </p>
            <p class="text-xs text-slate-400 mt-1">with no assignable agent</p>
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
                        {job_label(match.job)}
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
end
