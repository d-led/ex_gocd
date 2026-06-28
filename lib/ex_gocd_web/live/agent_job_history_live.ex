defmodule ExGoCDWeb.AgentJobHistoryLive do
  @moduledoc """
  LiveView for displaying agent job run history.
  Shows all jobs that have been executed on a specific agent.
  """
  use ExGoCDWeb, :live_view
  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents

  @impl true
  def mount(%{"uuid" => uuid}, _session, socket) do
    agent = Agents.get_agent_by_uuid(uuid)

    if agent do
      if connected?(socket), do: AgentJobRuns.subscribe_job_runs(uuid)

      {:ok,
       socket
       |> assign(
         agent: agent,
         job_history: list_runs(uuid),
         page: 1,
         page_size: 50,
         total_pages: 1,
         page_title: "Agent Job Run History",
         current_path: "/agents/#{uuid}/job_run_history"
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Agent not found")
       |> push_navigate(to: "/agents")}
    end
  end

  @impl true
  def handle_info({event, _agent_uuid}, socket)
      when event in [:run_created, :run_updated] do
    uuid = socket.assigns.agent.uuid
    {:noreply, assign(socket, job_history: list_runs(uuid))}
  end

  @impl true
  def handle_event("previous_page", _params, socket) do
    new_page = max(socket.assigns.page - 1, 1)
    {:noreply, assign(socket, page: new_page)}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    new_page = min(socket.assigns.page + 1, socket.assigns.total_pages)
    {:noreply, assign(socket, page: new_page)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="agent-job-history-page">
      <%!-- Agent detail card --%>
      <div class="bg-white rounded-lg border border-gray-200 shadow-sm mb-6">
        <div class="px-5 py-4">
          <div class="flex items-center gap-3 mb-3">
            <h1 class="text-lg font-bold text-gray-900">{@agent.hostname}</h1>
            <% is_elastic = @agent.elastic_agent_id || @agent.elastic_plugin_id %>
            <span class={"inline-flex px-2 py-0.5 rounded-full text-xs font-medium #{if is_elastic, do: "bg-purple-100 text-purple-700", else: "bg-gray-100 text-gray-600"}"}>
              {if @agent.elastic_agent_id, do: "elastic", else: "regular"}
            </span>
          </div>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
            <div>
              <span class="text-gray-400 text-xs uppercase tracking-wide">UUID</span>
              <p class="font-mono text-xs text-gray-600 mt-0.5" title={@agent.uuid}>
                {String.slice(@agent.uuid, 0, 12)}…
              </p>
            </div>
            <div>
              <span class="text-gray-400 text-xs uppercase tracking-wide">IP Address</span>
              <p class="text-gray-700 mt-0.5">{@agent.ipaddress || "—"}</p>
            </div>
            <div>
              <span class="text-gray-400 text-xs uppercase tracking-wide">OS</span>
              <p class="text-gray-700 mt-0.5">{@agent.operating_system || "—"}</p>
            </div>
            <div>
              <span class="text-gray-400 text-xs uppercase tracking-wide">Sandbox</span>
              <p class="text-gray-700 mt-0.5 truncate">{@agent.working_dir || "—"}</p>
            </div>
            <div>
              <span class="text-gray-400 text-xs uppercase tracking-wide">Status</span>
              <p class="text-gray-700 mt-0.5">{@agent.state || "—"}</p>
            </div>
            <div>
              <span class="text-gray-400 text-xs uppercase tracking-wide">Free Space</span>
              <p class="text-gray-700 mt-0.5">{format_bytes(@agent.free_space)}</p>
            </div>
            <div>
              <span class="text-gray-400 text-xs uppercase tracking-wide">Resources</span>
              <p class="text-gray-700 mt-0.5">
                <%= if @agent.resources not in [nil, []] do %>
                  {@agent.resources |> Enum.join(", ")}
                <% else %>
                  <span class="text-gray-400">none</span>
                <% end %>
              </p>
            </div>
            <div>
              <span class="text-gray-400 text-xs uppercase tracking-wide">Environments</span>
              <p class="text-gray-700 mt-0.5">
                <%= if @agent.environments not in [nil, []] do %>
                  {@agent.environments |> Enum.join(", ")}
                <% else %>
                  <span class="text-gray-400">none</span>
                <% end %>
              </p>
            </div>
          </div>
        </div>
      </div>

      <div class="page-header">
        <h1 class="page-header_title">
          <span>Job Run History</span>
        </h1>
      </div>

      <!-- Pagination Top -->
      <div class="pagination-controls">
        <button
          type="button"
          class="btn-pagination"
          phx-click="previous_page"
          disabled={@page == 1}
        >
          Previous
        </button>
        <button
          type="button"
          class="btn-pagination"
          phx-click="next_page"
          disabled={@page >= @total_pages}
        >
          Next
        </button>
      </div>

      <!-- Job History Table -->
      <div class="job-history-table-container">
        <table class="job-history-table">
          <thead>
            <tr>
              <th class="sortable">
                Pipeline <i class="fa fa-sort" aria-hidden="true"></i>
              </th>
              <th class="sortable">
                Stage <i class="fa fa-sort" aria-hidden="true"></i>
              </th>
              <th class="sortable">
                Job <i class="fa fa-sort" aria-hidden="true"></i>
              </th>
              <th class="sortable">
                Result <i class="fa fa-sort" aria-hidden="true"></i>
              </th>
              <th>Job State Transitions</th>
            </tr>
          </thead>
          <tbody>
            <%= if length(@job_history) == 0 do %>
              <tr>
                <td colspan="5" class="empty-state">
                  No job history available for this agent
                </td>
              </tr>
            <% else %>
              <%= for job <- @job_history do %>
                <tr>
                  <td>{display_pipeline(job)}</td>
                  <td>{display_stage(job)}</td>
                  <td class="job-name-cell">
                    <%= if linkable_job?(job) do %>
                      <a
                        href={
                          "/go/tab/build/detail/#{job.pipeline_name}/#{job.pipeline_counter || 1}/#{job.stage_name}/#{job.stage_counter || 1}/#{job.job_name}"
                        }
                        class="job-link"
                      >
                        {display_name(job.job_name)}
                      </a>
                    <% else %>
                      <a
                        href={"/agents/#{@agent.uuid}/job_run_history/#{job.build_id}"}
                        class="job-link"
                        title="View console log"
                      >
                        {display_name(job.job_name)}
                      </a>
                    <% end %>
                  </td>
                  <td>
                    <span class={result_class(job.result)}>
                      {job.result || job.state || "—"}
                    </span>
                  </td>
                  <td class="state-transition-cell">
                    <%= if linkable_job?(job) do %>
                      <a
                        href={
                          "/go/tab/build/detail/#{job.pipeline_name}/#{job.pipeline_counter || 1}/#{job.stage_name}/#{job.stage_counter || 1}/#{job.job_name}"
                        }
                        class="state-transition-link"
                        title="View job state transitions"
                      >
                        <i class="fa fa-history" aria-hidden="true"></i>
                      </a>
                    <% else %>
                      <span class="state-transition-icon" title="No pipeline (ad hoc job)">
                        <i class="fa fa-history" aria-hidden="true"></i>
                      </span>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>

      <!-- Pagination Bottom -->
      <div class="pagination-controls">
        <button
          type="button"
          class="btn-pagination"
          phx-click="previous_page"
          disabled={@page == 1}
        >
          Previous
        </button>
        <button
          type="button"
          class="btn-pagination"
          phx-click="next_page"
          disabled={@page >= @total_pages}
        >
          Next
        </button>
      </div>
    </div>
    """
  end

  defp display_name(nil), do: "—"
  defp display_name(""), do: "—"
  defp display_name("unknown"), do: "—"
  defp display_name(name), do: name

  # Ad hoc test jobs (Run test job) have no real pipeline; only link when we have a real pipeline.
  defp linkable_job?(job) do
    not use_mock?() and real_pipeline?(job) and real_stage?(job) and real_job?(job)
  end

  defp real_pipeline?(job) do
    job.pipeline_name not in [nil, "", "unknown", "test-pipeline"]
  end

  defp real_stage?(job) do
    job.stage_name not in [nil, "", "unknown", "test-stage"]
  end

  defp real_job?(job) do
    job.job_name not in [nil, "", "unknown"]
  end

  # Show "—" for pipeline/stage when it's an ad hoc test job (no pipeline in the system).
  defp display_pipeline(job) do
    if job.pipeline_name in [nil, "", "unknown", "test-pipeline"],
      do: "—",
      else: job.pipeline_name
  end

  defp display_stage(job) do
    if job.stage_name in [nil, "", "unknown", "test-stage"], do: "—", else: job.stage_name
  end

  defp result_class("Passed"), do: "result-passed"
  defp result_class("Failed"), do: "result-failed"
  defp result_class("Cancelled"), do: "result-cancelled"
  defp result_class("Unknown"), do: "result-unknown"
  defp result_class(_), do: "result-unknown"

  defp use_mock? do
    System.get_env("USE_MOCK_DATA") == "true"
  end

  defp list_runs(uuid) do
    if use_mock?() do
      [
        %ExGoCD.AgentJobRuns.AgentJobRun{
          id: 1,
          agent_uuid: uuid,
          build_id: "demo-build-1",
          pipeline_name: "demo",
          pipeline_counter: 1,
          stage_name: "build",
          stage_counter: 1,
          job_name: "default",
          state: "Completed",
          result: "Passed",
          console_log: "Hello, this is a mock console log from static mock data!\n",
          inserted_at: ~N[2026-02-05 10:30:00]
        }
      ]
    else
      AgentJobRuns.list_runs_for_agent(uuid)
    end
  end

  defp format_bytes(nil), do: "—"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
end
