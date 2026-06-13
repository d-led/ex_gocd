# Copyright 2026 ex_gocd
# GoCD-style job scheduler: reloads scheduled jobs from database; assigns work to idle agents
# when they ping. Matches by resources and environments (same semantics as BuildAssignmentService).

defmodule ExGoCD.Scheduler do
  use GenServer

  import Ecto.Query

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.JobInstance
  alias ExGoCD.PubSub
  alias ExGoCD.Repo
  alias ExGoCDWeb.AgentPresence

  @agent_topic_prefix "agent:"
  @presence_topic "agent"
  @scheduler_topic "scheduler:updates"

  # Client API

  @doc """
  Subscribes to scheduler queue updates (topic `scheduler:updates`).
  Events: `{:pending_count, count}`. LiveViews use this to update "Queued jobs" in real time.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(PubSub, @scheduler_topic)
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueues a job for assignment to an idle agent. Returns the job id (for reference).
  Used primarily by tests or dynamic tasks.

  Spec:
  - pipeline, stage, job (required)
  - resources (optional) — list of required resource tags; agent must have all
  - environments (optional) — list of env names; agent must be in at least one
  - build_command (optional) — %{"name" => _, "command" => _, "args" => _}
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

  @doc """
  Clears the pending queue. For test use only (ensures resource/environment matching
  tests see only the job they enqueue).
  """
  def clear_queue do
    GenServer.call(__MODULE__, :clear_queue)
  end

  # Server

  @impl true
  def init(_opts) do
    # Schedule initial reload if configured
    interval = Application.get_env(:ex_gocd, :scheduler_reload_interval, 5000)
    if interval && interval != :none do
      send(self(), :reload_jobs)
    end
    {:ok, %{in_memory_queue: [], timer: nil}}
  end

  @impl true
  def handle_call({:schedule_job, spec}, _from, %{in_memory_queue: in_memory_queue} = state) do
    if spec[:job_instance_id] do
      # Trigger assignment for idle agents immediately
      trigger_assignment_for_idle_agents()

      # Broadcast new combined pending count
      db_count = get_db_scheduled_count()
      broadcast_pending_count(length(in_memory_queue) + db_count)

      {:reply, {:ok, "db-#{spec.job_instance_id}"}, state}
    else
      id = "sched-#{System.unique_integer([:positive])}"
      entry = Map.put(spec, :id, id)
      new_queue = in_memory_queue ++ [entry]
      
      # Broadcast new combined pending count
      db_count = get_db_scheduled_count()
      broadcast_pending_count(length(new_queue) + db_count)

      # Trigger assignment for idle agents immediately
      trigger_assignment_for_idle_agents()

      {:reply, {:ok, id}, %{state | in_memory_queue: new_queue}}
    end
  end

  def handle_call({:try_assign_work, agent_uuid}, _from, state) do
    if Map.has_key?(AgentPresence.list(@presence_topic), agent_uuid) do
      case Agents.get_agent_by_uuid(agent_uuid) do
        nil ->
          {:reply, :agent_not_found, state}

        agent ->
          try_assign_to_idle_agent(agent_uuid, agent, state)
      end
    else
      {:reply, :agent_not_connected, state}
    end
  end

  def handle_call(:pending_count, _from, %{in_memory_queue: in_memory_queue} = state) do
    count = length(in_memory_queue) + get_db_scheduled_count()
    {:reply, count, state}
  end

  def handle_call(:clear_queue, _from, state) do
    # Clear both in-memory queue and database-backed scheduled runs in test env
    clear_db_scheduled_runs()
    broadcast_pending_count(0)
    {:reply, :ok, %{state | in_memory_queue: []}}
  end

  @impl true
  def handle_info(:reload_jobs, state) do
    # Cancel old timer if any
    if state.timer, do: Process.cancel_timer(state.timer)

    # Try assigning work to connected idle agents when reloading
    trigger_assignment_for_idle_agents()

    # Broadcast updated pending count
    db_count = get_db_scheduled_count()
    broadcast_pending_count(length(state.in_memory_queue) + db_count)

    # Schedule next reload if configured
    interval = Application.get_env(:ex_gocd, :scheduler_reload_interval, 5000)
    timer =
      if interval && interval != :none do
        Process.send_after(self(), :reload_jobs, interval)
      else
        nil
      end

    {:noreply, %{state | timer: timer}}
  end

  @impl true
  def handle_info({:assign_work_to_agent, agent_uuid}, state) do
    new_state =
      if Map.has_key?(AgentPresence.list(@presence_topic), agent_uuid) do
        case Agents.get_agent_by_uuid(agent_uuid) do
          nil ->
            state

          agent ->
            case try_assign_to_idle_agent(agent_uuid, agent, state) do
              {:reply, _reply, updated_state} -> updated_state
            end
        end
      else
        state
      end

    {:noreply, new_state}
  end

  # Helpers & Matching Logic

  defp try_assign_to_idle_agent(agent_uuid, agent, %{in_memory_queue: in_memory_queue} = state) do
    if agent.state != "Idle" do
      {:reply, :agent_busy, state}
    else
      # Load unified list of active job plans (in-memory + database)
      active_plans = in_memory_queue ++ load_db_job_plans()

      case find_matching_job(agent, active_plans) do
        nil ->
          {:reply, :no_work, state}

        {job_spec, _rest} ->
          assign_and_send(agent_uuid, agent, job_spec)
          
          # Remove from in-memory queue if it was an in-memory job
          new_in_memory =
            if String.starts_with?(to_string(job_spec.id), "sched-") do
              Enum.reject(in_memory_queue, &(&1.id == job_spec.id))
            else
              in_memory_queue
            end

          db_count = get_db_scheduled_count()
          broadcast_pending_count(length(new_in_memory) + db_count)

          {:reply, :assigned, %{state | in_memory_queue: new_in_memory}}
      end
    end
  end

  defp normalize_job_spec(spec) do
    base = %{
      pipeline: get_val(spec, "pipeline", :pipeline, "default-pipeline"),
      pipeline_counter: get_val(spec, "pipeline_counter", :pipeline_counter, 1),
      stage: get_val(spec, "stage", :stage, "default-stage"),
      stage_counter: get_val(spec, "stage_counter", :stage_counter, 1),
      job: get_val(spec, "job", :job, "default-job"),
      resources: get_val(spec, "resources", :resources, []),
      environments: get_val(spec, "environments", :environments, []),
      build_command: get_val(spec, "build_command", :build_command, nil),
      agent_uuid: get_val(spec, "agent_uuid", :agent_uuid, nil)
    }

    case Map.get(spec, "job_instance_id") || Map.get(spec, :job_instance_id) do
      id when is_integer(id) -> Map.put(base, :job_instance_id, id)
      _ -> base
    end
  end

  defp get_val(spec, key_str, key_atom, default) do
    Map.get(spec, key_str) || Map.get(spec, key_atom) || default
  end

  # Matches resources (subset) and environments
  defp find_matching_job(agent, queue) do
    agent_resources = MapSet.new(agent.resources |> Enum.map(&String.downcase/1))
    agent_envs = MapSet.new(agent.environments |> Enum.map(&String.downcase/1))

    idx =
      Enum.find_index(queue, fn spec ->
        cond do
          # Pinned to specific agent: must match exactly
          is_binary(spec[:agent_uuid]) and spec[:agent_uuid] != "" ->
            spec[:agent_uuid] == agent.uuid

          # Regular matching
          true ->
            resources_match?(spec.resources || [], agent_resources) and
              envs_match?(spec.environments || [], agent_envs)
        end
      end)

    if is_nil(idx) do
      nil
    else
      job = Enum.at(queue, idx)
      rest = List.delete_at(queue, idx)
      {job, rest}
    end
  end

  defp resources_match?(resources, agent_resources) do
    Enum.all?(resources, fn r ->
      MapSet.member?(agent_resources, String.downcase(r))
    end)
  end

  # Rule:
  # - Agent with no environments can only run jobs with no environments.
  # - Agent with environments can only run jobs with environments that match.
  defp envs_match?(job_envs, agent_envs) do
    job_envs_lower = Enum.map(job_envs || [], &String.downcase/1)
    
    if MapSet.equal?(agent_envs, MapSet.new()) do
      Enum.empty?(job_envs_lower)
    else
      not Enum.empty?(job_envs_lower) and
        Enum.any?(job_envs_lower, &MapSet.member?(agent_envs, &1))
    end
  end

  # Load scheduled JobInstances from database, preloading staging & pipeline details
  defp load_db_job_plans do
    safe_db(fn ->
      JobInstance
      |> where(state: "Scheduled")
      |> order_by(asc: :id)
      |> Repo.all()
      |> Repo.preload([:job, stage_instance: [pipeline_instance: :pipeline]])
      |> Enum.map(fn ji ->
        stage_instance = ji.stage_instance
        pipeline_instance = stage_instance.pipeline_instance
        pipeline = pipeline_instance.pipeline
        job_config = ji.job

        resources = (job_config && job_config.resources) || []
        envs = get_pipeline_environments(pipeline.name)
        build_command = build_command_from_job_instance(ji)

        %{
          id: "db-#{ji.id}",
          job_instance_id: ji.id,
          pipeline: pipeline.name,
          pipeline_counter: pipeline_instance.counter,
          stage: stage_instance.name,
          stage_counter: stage_instance.counter,
          job: ji.name,
          resources: resources,
          environments: envs,
          build_command: build_command
        }
      end)
    end, [])
  end

  # Dynamically generate Git checkout commands + Job Config tasks
  defp build_command_from_job_instance(ji) do
    stage_instance = ji.stage_instance
    pipeline_instance = stage_instance.pipeline_instance
    pipeline = pipeline_instance.pipeline
    job_config = ji.job

    # Prepend export commands for all environment variables (Environment -> Pipeline -> Stage -> Job)
    env_vars = get_all_job_env_vars(pipeline, stage_instance, job_config)
    export_cmds =
      Enum.map(env_vars, fn var ->
        %{
          "name" => "export",
          "args" => [var["name"], var["value"]]
        }
      end)

    # 1. Start with SCM checkout if stage_instance.fetch_materials is true
    checkout_cmds =
      if stage_instance.fetch_materials do
        build_cause = pipeline_instance.build_cause || %{}
        material_revisions = build_cause["materialRevisions"] || []

        Enum.flat_map(material_revisions, fn rev ->
          mat = rev["material"] || %{}
          modifications = rev["modifications"] || []
          mod = List.first(modifications) || %{}
          revision = mod["revision"] || "HEAD"

          if mat["type"] == "git" do
            url = mat["url"]
            branch = mat["branch"] || "master"
            dest = mat["destination"] || ""

            # Check if destination is empty or not
            mkdir_cmd =
              if dest != "" do
                [%{
                  "name" => "exec",
                  "command" => "mkdir",
                  "args" => ["-p", dest]
                }]
              else
                []
              end

            # Run git init, fetch, checkout in destination directory
            git_cmds = [
              %{
                "name" => "exec",
                "command" => "git",
                "args" => ["init"],
                "workingDirectory" => dest
              },
              %{
                "name" => "exec",
                "command" => "git",
                "args" => ["fetch", "--depth=1", url, branch],
                "workingDirectory" => dest
              },
              %{
                "name" => "exec",
                "command" => "git",
                "args" => ["checkout", revision],
                "workingDirectory" => dest
              }
            ]

            mkdir_cmd ++ git_cmds
          else
            []
          end
        end)
      else
        []
      end

    # 2. Add job tasks
    tasks = if job_config, do: Repo.preload(job_config, :tasks).tasks || [], else: []
    task_cmds =
      Enum.map(tasks, fn t ->
        %{
          "name" => t.type || "exec",
          "command" => t.command,
          "args" => t.arguments || [],
          "workingDirectory" => t.working_directory || ""
        }
      end)

    # 3. Combine them into compose structure: exports must come first!
    all_cmds = export_cmds ++ checkout_cmds ++ task_cmds

    # Default to echo if empty
    all_cmds =
      if Enum.empty?(all_cmds) do
        [%{"name" => "exec", "command" => "echo", "args" => ["No tasks configured"]}]
      else
        all_cmds
      end

    %{
      "name" => "compose",
      "subCommands" => all_cmds
    }
  end

  # Helper to resolve environment name for a pipeline (using database or fallback)
  defp get_pipeline_environments(pipeline_name) do
    if Application.get_env(:ex_gocd, :use_mock_data) == "true" or
       System.get_env("USE_MOCK_DATA") == "true" do
      case Enum.find(ExGoCD.MockData.pipelines_by_environment(), fn {_env, pipelines} ->
        Enum.any?(pipelines, &(&1.name == pipeline_name))
      end) do
        nil -> []
        {env, _} -> [env]
      end
    else
      case ExGoCD.Environments.get_pipeline_environment(pipeline_name) do
        nil -> []
        env -> [env.name]
      end
    end
  end

  # Helper to aggregate all environment variables across all hierarchy levels
  defp get_all_job_env_vars(pipeline, stage_instance, job_config) do
    env_vars =
      if Application.get_env(:ex_gocd, :use_mock_data) == "true" or System.get_env("USE_MOCK_DATA") == "true" do
        []
      else
        case ExGoCD.Environments.get_pipeline_environment(pipeline.name) do
          nil -> []
          env -> env.environment_variables || []
        end
      end

    pipe_vars = map_to_gocd_vars(pipeline.environment_variables)

    stage_config =
      if Application.get_env(:ex_gocd, :use_mock_data) == "true" or System.get_env("USE_MOCK_DATA") == "true" do
        nil
      else
        Repo.get_by(ExGoCD.Pipelines.Stage, pipeline_id: pipeline.id, name: stage_instance.name)
      end
    stage_vars = if stage_config, do: map_to_gocd_vars(stage_config.environment_variables), else: []

    job_vars = if job_config, do: map_to_gocd_vars(job_config.environment_variables), else: []

    merge_env_vars(env_vars, pipe_vars, stage_vars, job_vars)
  end

  defp map_to_gocd_vars(nil), do: []
  defp map_to_gocd_vars(vars) when is_map(vars) do
    Enum.map(vars, fn {k, v} ->
      case v do
        %{"value" => val} -> %{"name" => to_string(k), "value" => to_string(val)}
        val -> %{"name" => to_string(k), "value" => to_string(val)}
      end
    end)
  end
  defp map_to_gocd_vars(_), do: []

  defp merge_env_vars(env, pipe, stage, job) do
    norm_env = list_to_var_map(env)
    norm_pipe = list_to_var_map(pipe)
    norm_stage = list_to_var_map(stage)
    norm_job = list_to_var_map(job)

    merged =
      norm_env
      |> Map.merge(norm_pipe)
      |> Map.merge(norm_stage)
      |> Map.merge(norm_job)

    Map.values(merged)
  end

  defp list_to_var_map(list) do
    Enum.reduce(list || [], %{}, fn var, acc ->
      name = Map.get(var, "name") || Map.get(var, :name)
      if name do
        value = decrypt_variable(var)
        Map.put(acc, name, %{"name" => name, "value" => value})
      else
        acc
      end
    end)
  end

  defp decrypt_variable(var) do
    cond do
      val = Map.get(var, "value") || Map.get(var, :value) ->
        to_string(val)

      enc = Map.get(var, "encrypted_value") || Map.get(var, :encrypted_value) ->
        case Base.decode64(to_string(enc)) do
          {:ok, decoded} -> decoded
          _ -> to_string(enc)
        end

      true ->
        ""
    end
  end

  defp get_db_scheduled_count do
    safe_db(fn ->
      Repo.one(from(ji in JobInstance, where: ji.state == "Scheduled", select: count(ji.id)))
    end, 0)
  end

  defp clear_db_scheduled_runs do
    safe_db(fn ->
      Repo.delete_all(from(ji in JobInstance, where: ji.state == "Scheduled"))
    end, {0, nil})
  end

  # Triggers try_assign_work for all currently connected idle agents
  defp trigger_assignment_for_idle_agents do
    connected_agents = AgentPresence.list(@presence_topic)
    for {agent_uuid, _meta} <- connected_agents do
      send(self(), {:assign_work_to_agent, agent_uuid})
    end
    :ok
  end

  defp assign_and_send(agent_uuid, agent, job_spec) do
    build_id = "build-#{System.unique_integer([:positive])}"
    pipeline = job_spec.pipeline
    pipeline_counter = job_spec.pipeline_counter
    stage = job_spec.stage
    stage_counter = job_spec.stage_counter
    job = job_spec.job
    build_locator = "#{pipeline}/#{pipeline_counter}/#{stage}/#{stage_counter}/#{job}/1"

    build_command =
      (job_spec.build_command || %{"name" => "default", "command" => "echo", "args" => ["scheduled job ok"]})
      |> maybe_put_working_dir(agent)

    console_uri = ExGoCDWeb.Endpoint.url() <> "/api/builds/" <> build_id <> "/console"
    artifact_upload_base_url = ExGoCDWeb.Endpoint.url() <> "/files/#{pipeline}/#{pipeline_counter}/#{stage}/#{stage_counter}/#{job}"

    payload = %{
      "buildId" => build_id,
      "buildLocator" => build_locator,
      "buildLocatorForDisplay" => build_locator,
      "buildCommand" => build_command,
      "consoleURI" => console_uri,
      "artifactUploadBaseUrl" => artifact_upload_base_url
    }

    opts = [
      job_instance_id: job_spec[:job_instance_id],
      pipeline_counter: pipeline_counter,
      stage_counter: stage_counter
    ]
    case AgentJobRuns.create_run(agent_uuid, build_id, pipeline, stage, job, opts) do
      {:ok, _} ->
        if ji_id = job_spec[:job_instance_id], do: Pipelines.assign_job_instance(ji_id, agent_uuid)
        Agents.update_agent_runtime_state(agent_uuid, "Building")
        topic = @agent_topic_prefix <> agent_uuid
        Phoenix.PubSub.broadcast(PubSub, topic, {:build, payload})

      {:error, _} ->
        :ok
    end
  end

  defp broadcast_pending_count(count) do
    Phoenix.PubSub.broadcast(PubSub, @scheduler_topic, {:pending_count, count})
  end

  defp maybe_put_working_dir(cmd, agent) when is_map(cmd) do
    case agent.working_dir do
      dir when is_binary(dir) and dir != "" -> Map.put(cmd, "workingDirectory", dir)
      _ -> cmd
    end
  end

  # Safe DB execution helper to prevent Sandbox crashes in test mode
  defp safe_db(fun, fallback) do
    try do
      fun.()
    rescue
      _ -> fallback
    catch
      _, _ -> fallback
    end
  end
end
