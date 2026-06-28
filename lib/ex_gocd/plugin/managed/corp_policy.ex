defmodule ExGoCD.Plugin.Managed.CorpPolicy do
  @moduledoc """
  Example AgentSelector plugin: corporate scheduling policy.

  Rules:
  - GPU jobs ("gpu" resource) must never run on elastic (spot) agents.
  - "deploy" jobs must only run on agents tagged "production".

  Configure:

      config :ex_gocd, :plugins,
        agent_selector: ExGoCD.Plugin.Managed.CorpPolicy
  """

  @behaviour ExGoCD.Plugin.AgentSelector

  @impl true
  def select_candidates(agents, job_spec, _opts) do
    job_name = Map.get(job_spec, :job) || Map.get(job_spec, "job", "")
    resources = Map.get(job_spec, :resources) || Map.get(job_spec, "resources", [])
    needs_gpu? = "gpu" in resources
    is_deploy? = String.contains?(String.downcase(job_name), "deploy")

    agents
    |> maybe_reject_gpu_on_spot(needs_gpu?)
    |> maybe_require_production(is_deploy?)
  end

  defp maybe_reject_gpu_on_spot(agents, false), do: {:ok, agents}

  defp maybe_reject_gpu_on_spot(agents, true) do
    filtered = Enum.reject(agents, &(&1[:elastic_agent_id] not in [nil, ""]))
    if filtered == [], do: {:reject, "GPU jobs require non-spot agents"}, else: {:ok, filtered}
  end

  defp maybe_require_production({:reject, _} = result, _), do: result

  defp maybe_require_production({:ok, agents}, false), do: {:ok, agents}

  defp maybe_require_production({:ok, agents}, true) do
    prod = Enum.filter(agents, &("production" in (&1[:environments] || [])))
    if prod == [], do: {:reject, "Deploy jobs require production agents"}, else: {:ok, prod}
  end
end
