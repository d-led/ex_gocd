defmodule ExGoCDWeb.AgentJobHistoryLive do
  @moduledoc """
  LiveView for displaying agent job run history.
  Shows all jobs that have been executed on a specific agent.
  """
  use ExGoCDWeb, :live_view
  alias ExGoCD.Agents
  alias ExGoCD.AgentJobRuns

  @impl true
  def mount(%{"uuid" => uuid}, _session, socket) do
    agent = Agents.get_agent_by_uuid(uuid)

    if agent do
      AgentJobRuns.subscribe_job_runs(uuid)

      {:ok,
       socket
       |> assign(
         agent: agent,
         job_history: AgentJobRuns.list_runs_for_agent(uuid),
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
    {:noreply, assign(socket, job_history: AgentJobRuns.list_runs_for_agent(uuid))}
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
      <div class="page-header">
        <h1 class="page-header_title">
          <span>Agent Job Run History</span>
        </h1>
        <div class="agent-info">
          <span class="agent-hostname">{@agent.hostname}</span>
        </div>
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
    real_pipeline? = job.pipeline_name && job.pipeline_name != "" &&
      job.pipeline_name != "unknown" && job.pipeline_name != "test-pipeline"
    real_stage? = job.stage_name && job.stage_name != "" &&
      job.stage_name != "unknown" && job.stage_name != "test-stage"
    real_job? = job.job_name && job.job_name != "" && job.job_name != "unknown"
    real_pipeline? && real_stage? && real_job?
  end

  # Show "—" for pipeline/stage when it's an ad hoc test job (no pipeline in the system).
  defp display_pipeline(job) do
    if job.pipeline_name in [nil, "", "unknown", "test-pipeline"], do: "—", else: job.pipeline_name
  end

  defp display_stage(job) do
    if job.stage_name in [nil, "", "unknown", "test-stage"], do: "—", else: job.stage_name
  end

  defp result_class("Passed"), do: "result-passed"
  defp result_class("Failed"), do: "result-failed"
  defp result_class("Cancelled"), do: "result-cancelled"
  defp result_class("Unknown"), do: "result-unknown"
  defp result_class(_), do: "result-unknown"
end
