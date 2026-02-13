defmodule ExGoCDWeb.AgentJobRunDetailLive do
  @moduledoc """
  LiveView for a single job run: shows run metadata and console log (streamed from agent).
  """
  use ExGoCDWeb, :live_view
  alias ExGoCD.Agents
  alias ExGoCD.AgentJobRuns

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
        AgentJobRuns.subscribe_console(build_id)

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
        </div>
      </div>
      <pre class="console-log"><%= @run.console_log || "" %></pre>
    </div>
    """
  end

  defp result_class("Passed"), do: "result-passed"
  defp result_class("Failed"), do: "result-failed"
  defp result_class(_), do: "result-unknown"
end
