defmodule ExGoCD.ConfigRepos.Translator do
  @moduledoc """
  Behaviour for external CI pipeline translators.

  Implementations translate an ExternalPipelineIR into GoCD pipeline attributes
  suitable for passing to `Pipelines.create_pipeline/1` or the config repo parser's upsert logic.
  """

  alias ExGoCD.ConfigRepos.ExternalPipelineIR

  @doc """
  Translates an IR into pipeline attributes.

  Returns `{:ok, pipeline_attrs}` or `{:error, reason}`.

  `selections` is a map with keys like:
    - `:mode` — "translate", "execute_act", "execute_gitlab", or "skip"
    - `:selected_jobs` — %{"included" => ["job_name", ...]} (nil = all)
    - `:selected_triggers` — %{"included" => ["push", ...]} (nil = all)
    - `:pipeline_name_prefix` — prefix for generated pipeline name
    - `:overrides` — map of manual overrides (env vars, resource tags, etc.)
  """
  @callback translate(ir :: ExternalPipelineIR.t(), selections :: map()) ::
              {:ok, map()} | {:error, String.t()}
end
