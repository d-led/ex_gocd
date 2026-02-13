# Copyright 2026 ex_gocd
# GoCD-style job scheduler: in-memory queue of pending jobs; assigns work to idle agents
# when they ping. Matches by resources and environments (same semantics as BuildAssignmentService).

defmodule ExGoCD.Scheduler do
  use GenServer

  alias ExGoCD.Agents
  alias ExGoCD.AgentJobRuns
  alias ExGoCD.PubSub
  alias ExGoCDWeb.AgentPresence

  @agent_topic_prefix "agent:"
  @presence_topic "agent"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueues a job for assignment to an idle agent. Returns the job id (for reference).

  Spec:
  - pipeline, stage, job (required)
  - resources (optional) — list of required resource tags; agent must have all
  - environments (optional) — list of env names; agent must be in at least one
  - build_command (optional) — %{"name" => _, "command" => _, "args" => _}; default echo test
  """
  def schedule_job(spec) when is_map(spec) do
    GenServer.call(__MODULE__, {:schedule_job, normalize_job_spec(spec)})
  end

  @doc """
  Called when an agent pings with Idle. Tries to assign one pending job to this agent.
  Returns :assigned | :no_work | :agent_busy | :agent_not_connected | :agent_not_found.
  """
  def try_assign_work(agent_uuid) when is_binary(agent_uuid) do
    GenServer.call(__MODULE__, {:try_assign_work, agent_uuid})
  end

  @doc """
  Returns count of pending jobs in the queue (for UI).
  """
  def pending_count do
    GenServer.call(__MODULE__, :pending_count)
  end

  # Server

  @impl true
  def init(_opts) do
    {:ok, %{queue: []}}
  end

  @impl true
  def handle_call({:schedule_job, spec}, _from, %{queue: queue} = state) do
    id = "sched-#{System.unique_integer([:positive])}"
    entry = Map.put(spec, :id, id)
    {:reply, {:ok, id}, %{state | queue: queue ++ [entry]}}
  end

  def handle_call({:try_assign_work, agent_uuid}, _from, %{queue: queue} = state) do
    cond do
      not Map.has_key?(AgentPresence.list(@presence_topic), agent_uuid) ->
        {:reply, :agent_not_connected, state}

      is_nil(Agents.get_agent_by_uuid(agent_uuid)) ->
        {:reply, :agent_not_found, state}

      true ->
        agent = Agents.get_agent_by_uuid(agent_uuid)
        if agent.state != "Idle" do
          {:reply, :agent_busy, state}
        else
          case find_matching_job(agent, queue) do
            nil ->
              {:reply, :no_work, state}

            {job_spec, rest} ->
              assign_and_send(agent_uuid, agent, job_spec)
              {:reply, :assigned, %{state | queue: rest}}
          end
        end
    end
  end

  def handle_call(:pending_count, _from, %{queue: queue} = state) do
    {:reply, length(queue), state}
  end

  defp normalize_job_spec(spec) do
    %{
      pipeline: spec["pipeline"] || spec[:pipeline] || "default-pipeline",
      stage: spec["stage"] || spec[:stage] || "default-stage",
      job: spec["job"] || spec[:job] || "default-job",
      resources: spec["resources"] || spec[:resources] || [],
      environments: spec["environments"] || spec[:environments] || [],
      build_command: spec["build_command"] || spec[:build_command]
    }
  end

  defp find_matching_job(agent, queue) do
    agent_resources = MapSet.new((agent.resources || []) |> Enum.map(&String.downcase/1))
    agent_envs = MapSet.new((agent.environments || []) |> Enum.map(&String.downcase/1))

    idx =
      Enum.find_index(queue, fn spec ->
        resources_ok =
          (spec.resources || []) |> Enum.all?(fn r ->
            MapSet.member?(agent_resources, String.downcase(r))
          end)

        envs_ok =
          case spec.environments || [] do
            [] -> true
            envs ->
              Enum.any?(envs, fn e -> MapSet.member?(agent_envs, String.downcase(e)) end)
          end

        resources_ok and envs_ok
      end)

    if is_nil(idx) do
      nil
    else
      job = Enum.at(queue, idx)
      rest = List.delete_at(queue, idx)
      {job, rest}
    end
  end

  defp assign_and_send(agent_uuid, agent, job_spec) do
    build_id = "build-#{System.unique_integer([:positive])}"
    pipeline = job_spec.pipeline
    stage = job_spec.stage
    job = job_spec.job
    build_locator = "#{pipeline}/1/#{stage}/1/#{job}/1"

    build_command =
      (job_spec.build_command || %{"name" => "default", "command" => "echo", "args" => ["scheduled job ok"]})
      |> maybe_put_working_dir(agent)

    console_uri = ExGoCDWeb.Endpoint.url() <> "/api/builds/" <> build_id <> "/console"

    payload = %{
      "buildId" => build_id,
      "buildLocator" => build_locator,
      "buildLocatorForDisplay" => build_locator,
      "buildCommand" => build_command,
      "consoleURI" => console_uri
    }

    case AgentJobRuns.create_run(agent_uuid, build_id, pipeline, stage, job) do
      {:ok, _} ->
        Agents.update_agent_runtime_state(agent_uuid, "Building")
        topic = @agent_topic_prefix <> agent_uuid
        Phoenix.PubSub.broadcast(PubSub, topic, {:build, payload})

      {:error, _} ->
        :ok
    end
  end

  defp maybe_put_working_dir(cmd, agent) when is_map(cmd) do
    case agent.working_dir do
      dir when is_binary(dir) and dir != "" -> Map.put(cmd, "workingDirectory", dir)
      _ -> cmd
    end
  end
end
