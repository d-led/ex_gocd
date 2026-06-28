defmodule ExGoCD.Plugin.AgentSelector do
  @moduledoc """
  Post-match agent filter. Called after the scheduler has found candidate agents
  that satisfy resource/environment constraints. The plugin can narrow or reorder
  the list before one agent is picked.

  Return `{:ok, agents}` to use a filtered subset, or `{:reject, reason}` to
  veto the entire assignment (job stays queued).
  """

  @type agent :: ExGoCD.Agents.Agent.t()
  @type job_spec :: map()

  @callback select_candidates([agent()], job_spec(), keyword()) ::
              {:ok, [agent()]} | {:reject, String.t()}
end
