defmodule ExGoCD.AgentJobRuns do
  @moduledoc """
  Context for agent job run history. Creates runs when a build is sent,
  updates them when the agent reports status/completion.

  PubSub topics for LiveView updates:
  - `agent_job_runs:{agent_uuid}` — list of runs changed; payload `{:run_created | :run_updated, agent_uuid}`.
  - `agent_job_run_console:{build_id}` — console log appended `{:console_append, chunk}`; run state/result `{:run_updated, run}`.
  """
  import Ecto.Query
  alias ExGoCD.PubSub
  alias ExGoCD.Repo
  alias ExGoCD.Agents
  alias ExGoCD.AgentJobRuns.AgentJobRun

  @job_runs_topic_prefix "agent_job_runs:"
  @console_topic_prefix "agent_job_run_console:"

  @doc """
  Subscribes to job run list updates for an agent (topic `agent_job_runs:{agent_uuid}`).
  LiveViews use this to refetch the list when runs are created or updated.
  """
  def subscribe_job_runs(agent_uuid) when is_binary(agent_uuid) do
    Phoenix.PubSub.subscribe(PubSub, @job_runs_topic_prefix <> agent_uuid)
  end

  @doc """
  Subscribes to console log updates for a build (topic `agent_job_run_console:{build_id}`).
  LiveViews use this to append chunks in real time.
  """
  def subscribe_console(build_id) when is_binary(build_id) do
    Phoenix.PubSub.subscribe(PubSub, @console_topic_prefix <> build_id)
  end

  defp broadcast_job_runs(agent_uuid, event) when is_binary(agent_uuid) do
    Phoenix.PubSub.broadcast(PubSub, @job_runs_topic_prefix <> agent_uuid, {event, agent_uuid})
  end

  defp broadcast_console(build_id, chunk) when is_binary(build_id) and is_binary(chunk) do
    Phoenix.PubSub.broadcast(PubSub, @console_topic_prefix <> build_id, {:console_append, chunk})
  end

  @doc """
  Creates a job run when a build is sent to an agent (e.g. Run test job or pipeline trigger).
  Call before broadcasting the build so the run exists when the agent reports back.
  Options: :job_instance_id (integer) — when set, links this run to a pipeline JobInstance.
  """
  def create_run(agent_uuid, build_id, pipeline_name, stage_name, job_name, opts \\ [])
      when is_binary(agent_uuid) and is_binary(build_id) do
    job_instance_id = Keyword.get(opts, :job_instance_id)
    # Only link to job_instance if it exists (avoids FK violation when e.g. pipeline test rolled back but queue persists)
    job_instance_id = if job_instance_id && Repo.get(ExGoCD.Pipelines.JobInstance, job_instance_id), do: job_instance_id, else: nil
    case Agents.get_agent_by_uuid(agent_uuid) do
      nil -> {:error, :agent_not_found}
      _agent ->
        attrs = %{
          agent_uuid: agent_uuid,
          build_id: build_id,
          pipeline_name: pipeline_name,
          stage_name: stage_name,
          job_name: job_name,
          state: "Assigned"
        }
        attrs = if job_instance_id, do: Map.put(attrs, :job_instance_id, job_instance_id), else: attrs
        result =
          %AgentJobRun{}
          |> AgentJobRun.changeset(attrs)
          |> Repo.insert()

        if match?({:ok, _}, result), do: broadcast_job_runs(agent_uuid, :run_created)
        result
    end
  end

  @doc """
  Updates a job run when the agent reports status (reportCurrentStatus, reportCompleting, reportCompleted).
  """
  def report_status(agent_uuid, build_id, job_state, result \\ nil) do
    run =
      from(r in AgentJobRun,
        where: r.agent_uuid == ^agent_uuid and r.build_id == ^build_id,
        limit: 1
      )
      |> Repo.one()

    if run do
      attrs = %{state: job_state}
      attrs = if result, do: Map.put(attrs, :result, result), else: attrs
      case run |> AgentJobRun.changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          broadcast_job_runs(agent_uuid, :run_updated)
          broadcast_run_updated_for_console(build_id, updated)
          if updated.job_instance_id && job_state == "Completed" && result do
            ExGoCD.Pipelines.complete_job_instance(updated.job_instance_id, result)
          end
          {:ok, updated}
        error ->
          error
      end
    else
      {:error, :run_not_found}
    end
  end

  @doc """
  Handles agent report messages (reportCurrentStatus, reportCompleting, reportCompleted).
  Updates job run state and agent runtime state. Call from the agent channel to keep channel thin.
  """
  def handle_agent_report(agent_uuid, payload) when is_binary(agent_uuid) and is_map(payload) do
    build_id = payload["buildId"]
    job_state = payload["jobState"]
    result = payload["result"]
    if build_id && job_state, do: report_status(agent_uuid, build_id, job_state, result)
    runtime_status = payload["agentRuntimeInfo"] && payload["agentRuntimeInfo"]["runtimeStatus"]
    if runtime_status, do: Agents.update_agent_runtime_state(agent_uuid, runtime_status)
    :ok
  end

  defp broadcast_run_updated_for_console(build_id, run) when is_binary(build_id) do
    Phoenix.PubSub.broadcast(PubSub, @console_topic_prefix <> build_id, {:run_updated, run})
  end

  @doc """
  Appends console output to a job run by build_id. Used when the agent POSTs console log.
  """
  def append_console(build_id, chunk) when is_binary(build_id) and is_binary(chunk) do
    run =
      from(r in AgentJobRun, where: r.build_id == ^build_id, limit: 1)
      |> Repo.one()

    if run do
      new_log = (run.console_log || "") <> chunk
      result = run |> AgentJobRun.changeset(%{console_log: new_log}) |> Repo.update()
      if match?({:ok, _}, result), do: broadcast_console(build_id, chunk)
      result
    else
      {:error, :run_not_found}
    end
  end

  @doc """
  Returns a single job run by agent UUID and build_id, or nil.
  """
  def get_run(agent_uuid, build_id)
      when is_binary(agent_uuid) and is_binary(build_id) do
    from(r in AgentJobRun,
      where: r.agent_uuid == ^agent_uuid and r.build_id == ^build_id,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists job runs for an agent (by UUID), newest first, for the history page.
  """
  def list_runs_for_agent(agent_uuid) when is_binary(agent_uuid) do
    from(r in AgentJobRun,
      where: r.agent_uuid == ^agent_uuid,
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
  end
end
