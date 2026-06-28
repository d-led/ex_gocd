defmodule ExGoCD.Plugin.PipelineGrouper do
  @moduledoc """
  Computes pipeline groups dynamically. Called when the pipeline list is
  fetched (dashboard, admin, API). May consult external data (LDAP, GitHub teams,
  config repo metadata).
  """

  @type pipeline :: ExGoCD.Pipelines.Pipeline.t()
  @type group_name :: String.t()

  @callback compute_groups([pipeline()], keyword()) :: %{group_name() => [pipeline()]}
  @callback group_for_pipeline(pipeline(), keyword()) :: group_name()
end
