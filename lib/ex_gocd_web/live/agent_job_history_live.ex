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
         current_path: "/agents/#{uuid}/job_run_history",
         transition_modal_job: nil
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

  def handle_event("show_transitions", %{"index" => index}, socket) do
    job = Enum.at(socket.assigns.job_history, String.to_integer(index))
    {:noreply, assign(socket, transition_modal_job: job)}
  end

  def handle_event("close_transitions", _params, socket) do
    {:noreply, assign(socket, transition_modal_job: nil)}
  end

  def handle_event("close_transitions_escape", %{"key" => "Escape"}, socket) do
    if socket.assigns.transition_modal_job do
      {:noreply, assign(socket, transition_modal_job: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_transitions_escape", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="agent-job-history-page" phx-window-keydown="close_transitions_escape">
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
              <%= for {job, idx} <- Enum.with_index(@job_history) do %>
                <tr>
                  <td>{job.pipeline_name}</td>
                  <td>{job.stage_name}</td>
                  <td>
                    <a
                      href="#"
                      class="job-link"
                      title="Build detail (not yet implemented)"
                    >
                      {job.job_name}
                    </a>
                  </td>
                  <td>
                    <span class={result_class(job.result)}>
                      {job.result}
                    </span>
                  </td>
                  <td>
                    <button
                      type="button"
                      class="state-transition-icon"
                      title="View job state transitions"
                      phx-click="show_transitions"
                      phx-value-index={to_string(idx)}
                      aria-label="View state transitions for #{job.job_name}"
                    >
                      <i class="fa fa-history" aria-hidden="true"></i>
                    </button>
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

      <%= if @transition_modal_job do %>
        <div
          class="job-transitions-modal-overlay"
          role="dialog"
          aria-modal="true"
          aria-label="Job state transitions"
        >
          <div class="job-transitions-modal">
            <div class="job-transitions-modal-content">
              <h3>Job State Transitions — {@transition_modal_job.job_name}</h3>
              <ul class="job-transitions-list">
                <%= for t <- @transition_modal_job.job_state_transitions || [] do %>
                  <li>
                    <span class="transition-state">{t.state}</span>
                    <span class="transition-time">{format_transition_time(t.state_change_time)}</span>
                  </li>
                <% end %>
              </ul>
              <button type="button" class="btn-small" phx-click="close_transitions">Close</button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp fetch_job_history(uuid) do
    # When job execution is implemented, query job instances by agent_uuid from Pipelines context.
    # For now return mock data so the page demonstrates the full UI (table + state transitions).
    mock_job_history(uuid)
  end

  defp mock_job_history(_uuid) do
    [
      %{
        pipeline_name: "build-linux",
        pipeline_counter: 145,
        stage_name: "build",
        stage_counter: 1,
        job_name: "compile",
        result: "Passed",
        job_state_transitions: [
          %{state: "Scheduled", state_change_time: ~N[2026-02-05 10:00:00]},
          %{state: "Assigned", state_change_time: ~N[2026-02-05 10:00:05]},
          %{state: "Preparing", state_change_time: ~N[2026-02-05 10:00:10]},
          %{state: "Building", state_change_time: ~N[2026-02-05 10:00:15]},
          %{state: "Completing", state_change_time: ~N[2026-02-05 10:05:22]},
          %{state: "Completed", state_change_time: ~N[2026-02-05 10:05:25]}
        ]
      },
      %{
        pipeline_name: "build-linux",
        pipeline_counter: 145,
        stage_name: "build",
        stage_counter: 1,
        job_name: "test",
        result: "Passed",
        job_state_transitions: [
          %{state: "Scheduled", state_change_time: ~N[2026-02-05 10:05:30]},
          %{state: "Assigned", state_change_time: ~N[2026-02-05 10:05:35]},
          %{state: "Building", state_change_time: ~N[2026-02-05 10:05:40]},
          %{state: "Completed", state_change_time: ~N[2026-02-05 10:08:00]}
        ]
      },
      %{
        pipeline_name: "deploy-staging",
        pipeline_counter: 234,
        stage_name: "deploy",
        stage_counter: 1,
        job_name: "deploy",
        result: "Passed",
        job_state_transitions: [
          %{state: "Scheduled", state_change_time: ~N[2026-02-05 09:00:00]},
          %{state: "Assigned", state_change_time: ~N[2026-02-05 09:00:02]},
          %{state: "Building", state_change_time: ~N[2026-02-05 09:00:05]},
          %{state: "Completed", state_change_time: ~N[2026-02-05 09:02:10]}
        ]
      }
    ]
  end

  defp format_transition_time(naive_dt) when is_struct(naive_dt, NaiveDateTime) do
    Calendar.strftime(naive_dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_transition_time(_), do: "—"

  defp result_class("Passed"), do: "result-passed"
  defp result_class("Failed"), do: "result-failed"
  defp result_class("Cancelled"), do: "result-cancelled"
  defp result_class("Unknown"), do: "result-unknown"
  defp result_class(_), do: "result-unknown"
end
