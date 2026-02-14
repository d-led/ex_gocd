defmodule ExGoCDWeb.AgentJobRunDetailLive do
  @moduledoc """
  LiveView for a single job run: shows run metadata and console log (streamed from agent).
  Cancel button shown when run is still building; requests agent to cancel via channel.
  """
  use ExGoCDWeb, :live_view
  alias ExGoCD.Agents
  alias ExGoCD.AgentJobRuns
  alias ExGoCDWeb.AgentChannel

  @impl true
  def mount(%{"uuid" => uuid, "build_id" => build_id}, _session, socket) do
    agent = Agents.get_agent_by_uuid(uuid)
    run = AgentJobRuns.get_run(uuid, build_id)

    cond do
      is_nil(agent) ->
        {:ok,
         socket
         |> put_flash(:error, "Agent not found")
         |> push_navigate(to: "/agents")}

      is_nil(run) ->
        {:ok,
         socket
         |> put_flash(:error, "Job run not found")
         |> push_navigate(to: "/agents/#{uuid}/job_run_history")}

      true ->
        if connected?(socket), do: AgentJobRuns.subscribe_console(build_id)

        {:ok,
         socket
         |> assign(agent: agent, run: run, page_title: "Console: #{run.job_name}")}
    end
  end

  @impl true
  def handle_info({:console_append, chunk}, socket) do
    run = socket.assigns.run
    new_console_log = (run.console_log || "") <> chunk
    updated_run = %{run | console_log: new_console_log}
    {:noreply, assign(socket, run: updated_run)}
  end

  def handle_info({:run_updated, updated_run}, socket) do
    # Agent reported completion; update run (e.g. result Passed/Failed/Cancelled) in real time
    if updated_run.build_id == socket.assigns.run.build_id do
      {:noreply, assign(socket, run: updated_run)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_build", _params, socket) do
    run = socket.assigns.run
    agent = socket.assigns.agent
    if run_cancellable?(run) do
      AgentChannel.request_cancel_build(agent.uuid, run.build_id)
      {:noreply,
       socket
       |> put_flash(:info, "Cancel requested. Agent will stop the build and report back.")}
    else
      {:noreply, put_flash(socket, :error, "Build is no longer running.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="agent-job-run-detail-page">
      <div class="page-header">
        <h1 class="page-header_title">
          <a href={"/agents/#{@agent.uuid}/job_run_history"} class="back-link">
            <i class="fa fa-arrow-left" aria-hidden="true"></i> Job Run History
          </a>
          <span>Console: {@run.job_name}</span>
        </h1>
        <div class="run-meta">
          <span>Build: {@run.build_id}</span>
          <span class={result_class(@run.result)}>{@run.result || @run.state || "—"}</span>
          <%= if run_cancellable?(@run) do %>
            <button
              type="button"
              class="btn-small btn-danger"
              phx-click="cancel_build"
              data-confirm="Stop this build on the agent?"
            >
              Cancel build
            </button>
          <% end %>
        </div>
      </div>
      <pre class="console-log"><%= @run.console_log || "" %></pre>
    </div>
    """
  end

  defp result_class("Passed"), do: "result-passed"
  defp result_class("Failed"), do: "result-failed"
  defp result_class("Cancelled"), do: "result-cancelled"
  defp result_class(_), do: "result-unknown"

  defp run_cancellable?(run) do
    run.state in ["Assigned", "Building", "Completing"]
  end
end
