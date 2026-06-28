defmodule ExGoCD.Plugin.Managed.RegionalAffinity do
  @moduledoc """
  AgentSelector plugin: prefers agents in the same region as the pipeline.
  Logs every scheduling decision to an in-memory ring buffer (last 200 entries)
  exposed via `decisions/0` and `decisions_for/1` (by pipeline).

  Always loaded as the default agent_selector. To swap it, override in config:

      config :ex_gocd, :plugins, agent_selector: MyApp.CustomSelector
  """

  use GenServer
  @behaviour ExGoCD.Plugin.AgentSelector

  @max_entries 200

  # -- Client API (behaviour callback, called by Scheduler) --

  @impl true
  def select_candidates(agents, job_spec, _opts) do
    result = do_select(agents, job_spec)
    record_decision(job_spec, agents, result)
    result
  end

  # -- Audit API (called by LiveView) --

  @doc "Returns all recent scheduling decisions, newest first."
  def decisions do
    try do
      GenServer.call(__MODULE__, :decisions)
    catch
      :exit, _ -> []
    end
  end

  @doc "Returns decisions for a specific pipeline."
  def decisions_for(pipeline_name) do
    decisions()
    |> Enum.filter(&(&1.pipeline == pipeline_name))
  end

  # -- GenServer (audit log) --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, []}
  end

  @impl true
  def handle_call(:decisions, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:log, entry}, state) do
    {:noreply, [entry | state] |> Enum.take(@max_entries)}
  end

  # -- Private --

  defp record_decision(job_spec, agents, result) do
    entry = %{
      timestamp: DateTime.utc_now(),
      pipeline: Map.get(job_spec, :pipeline) || Map.get(job_spec, "pipeline", "?"),
      stage: Map.get(job_spec, :stage) || Map.get(job_spec, "stage", "?"),
      job: Map.get(job_spec, :job) || Map.get(job_spec, "job", "?"),
      region: Map.get(job_spec, :region) || Map.get(job_spec, "region", "any"),
      resources: Map.get(job_spec, :resources) || Map.get(job_spec, "resources", []),
      agent_count: length(agents),
      decision: decision_label(result)
    }

    GenServer.cast(__MODULE__, {:log, entry})
  end

  defp decision_label({:ok, filtered}) do
    same = length(filtered)
    "accepted (preferred #{same} of #{0})"
  end

  defp decision_label({:reject, reason}), do: "rejected: #{reason}"

  defp do_select(agents, job_spec) do
    region = Map.get(job_spec, :region) || Map.get(job_spec, "region")

    if region do
      {same, others} =
        Enum.split_with(agents, fn agent ->
          agent_region(agent) == region
        end)

      {:ok, same ++ others}
    else
      {:ok, agents}
    end
  end

  defp agent_region(agent) do
    envs = Map.get(agent, :environments) || []
    region_env = Enum.find(envs, &String.starts_with?(&1, "region-"))
    if region_env, do: String.replace_prefix(region_env, "region-", ""), else: "unknown"
  end
end
