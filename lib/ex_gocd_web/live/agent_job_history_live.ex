defmodule ExGoCDWeb.AgentJobHistoryLive do
  @moduledoc """
  LiveView for displaying agent job run history.
  Shows all jobs that have been executed on a specific agent.
  """
  use ExGoCDWeb, :live_view
  alias ExGoCD.Agents

  @impl true
  def mount(%{"uuid" => uuid}, _session, socket) do
    agent = Agents.get_agent_by_uuid(uuid)

    if agent do
      {:ok,
       socket
       |> assign(
         agent: agent,
         job_history: fetch_job_history(uuid),
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
          <span class="agent-hostname"><%= @agent.hostname %></span>
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
                Pipeline
                <i class="fa fa-sort" aria-hidden="true"></i>
              </th>
              <th class="sortable">
                Stage
                <i class="fa fa-sort" aria-hidden="true"></i>
              </th>
              <th class="sortable">
                Job
                <i class="fa fa-sort" aria-hidden="true"></i>
              </th>
              <th class="sortable">
                Result
                <i class="fa fa-sort" aria-hidden="true"></i>
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
                  <td><%= job.pipeline_name %></td>
                  <td><%= job.stage_name %></td>
                  <td>
                    <a
                      href={
                        "/go/tab/build/detail/#{job.pipeline_name}/#{job.pipeline_counter}/#{job.stage_name}/#{job.stage_counter}/#{job.job_name}"
                      }
                      class="job-link"
                    >
                      <%= job.job_name %>
                    </a>
                  </td>
                  <td>
                    <span class={result_class(job.result)}>
                      <%= job.result %>
                    </span>
                  </td>
                  <td>
                    <div class="state-transition-icon" title="View job state transitions">
                      <i class="fa fa-history" aria-hidden="true"></i>
                    </div>
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

  defp fetch_job_history(_uuid) do
    # TODO: Implement actual job history fetching from database
    # Expected structure:
    # %{
    #   pipeline_name: "my-pipeline",
    #   pipeline_counter: 123,
    #   stage_name: "build",
    #   stage_counter: "1",
    #   job_name: "unit-tests",
    #   result: "Passed",
    #   job_state_transitions: [
    #     %{state: "Scheduled", state_change_time: ~N[...]},
    #     %{state: "Assigned", state_change_time: ~N[...]},
    #     ...
    #   ]
    # }
    []
  end

  defp result_class("Passed"), do: "result-passed"
  defp result_class("Failed"), do: "result-failed"
  defp result_class("Cancelled"), do: "result-cancelled"
  defp result_class("Unknown"), do: "result-unknown"
  defp result_class(_), do: "result-unknown"
end
