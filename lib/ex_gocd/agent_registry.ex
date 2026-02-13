# Copyright 2026 ex_gocd
# GenServer that handles test-job assignment. Uses Phoenix Presence to know which
# agents are connected; Presence tracks connection loss automatically (no manual
# unregister). Assignment logic lives here, not in the UI or channel.

defmodule ExGoCD.AgentRegistry do
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
  Request a test job for the given agent. Returns :ok if the agent is present
  (connected) and the build was dispatched; {:error, :agent_not_connected} if
  not in Presence; {:error, :invalid_uuid} for bad input.
  """
  def request_test_job(agent_uuid) when is_binary(agent_uuid) do
    GenServer.call(__MODULE__, {:request_test_job, agent_uuid})
  end

  def request_test_job(_), do: {:error, :invalid_uuid}

  @doc """
  Returns whether the given agent uuid has an active connection (present in Presence).
  """
  def connected?(agent_uuid) when is_binary(agent_uuid) do
    presences = AgentPresence.list(@presence_topic)
    Map.has_key?(presences, agent_uuid)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:request_test_job, agent_uuid}, _from, state) do
    presences = AgentPresence.list(@presence_topic)

    if Map.has_key?(presences, agent_uuid) do
      topic = @agent_topic_prefix <> agent_uuid
      {build_payload, build_id, pipeline, stage, job} = build_payload_for_test(agent_uuid)
      _ = AgentJobRuns.create_run(agent_uuid, build_id, pipeline, stage, job)
      Phoenix.PubSub.broadcast(PubSub, topic, {:build, build_payload})
      {:reply, :ok, state}
    else
      {:reply, {:error, :agent_not_connected}, state}
    end
  end

  defp build_payload_for_test(agent_uuid) do
    build_id = "test-job-#{System.unique_integer([:positive])}"
    build_locator = "test-pipeline/1/test-stage/1/test-job/1"
    pipeline = "test-pipeline"
    stage = "test-stage"
    job = "test-job"

    build_command =
      %{"name" => "test", "command" => "echo", "args" => ["ok"]}
      |> maybe_put_working_dir(agent_uuid)

    console_uri = console_uri_for_build(build_id)

    payload = %{
      "buildId" => build_id,
      "buildLocator" => build_locator,
      "buildLocatorForDisplay" => build_locator,
      "buildCommand" => build_command,
      "consoleURI" => console_uri
    }

    {payload, build_id, pipeline, stage, job}
  end

  defp console_uri_for_build(build_id) do
    base = ExGoCDWeb.Endpoint.url()
    base <> "/api/builds/" <> build_id <> "/console"
  end

  defp maybe_put_working_dir(cmd, agent_uuid) do
    case Agents.get_agent_by_uuid(agent_uuid) do
      %{working_dir: dir} when is_binary(dir) and dir != "" ->
        Map.put(cmd, "workingDirectory", dir)

      _ ->
        cmd
    end
  end
end
