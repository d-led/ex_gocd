defmodule ExGoCD.Plugin.Managed.RegionalAffinity do
  @moduledoc """
  Example AgentSelector plugin: prefers agents in the same region as the pipeline.

  Configure in dev.exs/prod.exs:

      config :ex_gocd, :plugins, agent_selector: ExGoCD.Plugin.Managed.RegionalAffinity

  If the job spec carries a `:region` key, agents matching that region are
  sorted to the front of the candidate list. Non-matching agents follow,
  preserving the original scheduler ordering within each group.
  """

  @behaviour ExGoCD.Plugin.AgentSelector

  @impl true
  def select_candidates(agents, job_spec, _opts) do
    region = Map.get(job_spec, :region) || Map.get(job_spec, "region")

    if region do
      {same, others} = Enum.split_with(agents, fn agent ->
        agent_region(agent) == region
      end)

      {:ok, same ++ others}
    else
      {:ok, agents}
    end
  end

  defp agent_region(agent) do
    # Agents can tag their region via an environment name like "us-east-1"
    envs = Map.get(agent, :environments) || []
    region_env = Enum.find(envs, &String.starts_with?(&1, "region-"))
    if region_env, do: String.replace_prefix(region_env, "region-", ""), else: "unknown"
  end
end
