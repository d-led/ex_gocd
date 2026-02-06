# Value Objects vs Ecto Schemas

## Overview

Not all GoCD domain classes should be mapped to Ecto schemas. Many are **value objects** or **composite identifiers** that should be represented as Elixir structs or records, not database-backed schemas.

## Criteria for Ecto Schemas vs Structs

### Use Ecto Schema When:
- Class has database persistence (tables, rows)
- Has an `id` field auto-generated
- Tracked across lifecycle changes
- Modified via CRUD operations
- Examples: `Pipeline`, `Stage`, `Job`, `PipelineInstance`, `StageInstance`, `JobInstance`

### Use Elixir Struct When:
- Class implements `Serializable` but not persisted separately
- Composite identifier/locator (identifies entities)
- Value object (immutable, no identity)
- Embedded as JSON/map in parent schema
- Examples: `BuildCause`, `JobIdentifier`, `StageIdentifier`, `MaterialRevisions`, `EnvironmentVariables`

## Non-Persistent Domain Objects in GoCD

### Identifiers (Locators)

These classes uniquely identify entities but aren't persisted separately:

| GoCD Class | Purpose | Elixir Representation | Storage |
|---|---|---|---|
| `JobIdentifier` | Composite key: pipeline/stage/job | `defstruct` | Stored as string in `job_instances.identifier` |
| `StageIdentifier` | Composite key: pipeline/stage | `defstruct` | Stored as string in `stage_instances.identifier` |
| `PipelineIdentifier` | Composite key: pipeline name + counter | `defstruct` | Not separately stored |

**Implementation:**
```elixir
defmodule ExGoCD.Domain.JobIdentifier do
  @moduledoc """
  Composite identifier for a job instance.
  Based on: domain/JobIdentifier.java
  """
  defstruct [
    :pipeline_name,
    :pipeline_counter,
    :pipeline_label,
    :stage_name,
    :stage_counter,
    :build_name,
    :build_id
  ]

  @type t :: %__MODULE__{
    pipeline_name: String.t(),
    pipeline_counter: integer(),
    pipeline_label: String.t(),
    stage_name: String.t(),
    stage_counter: String.t(),
    build_name: String.t(),
    build_id: integer()
  }

  # Stored as: "pipeline/123/stage/456/job"
  def to_string(%__MODULE__{} = id) do
    "#{id.pipeline_name}/#{id.pipeline_counter}/#{id.stage_name}/#{id.stage_counter}/#{id.build_name}"
  end

  def from_string(str) when is_binary(str) do
    # Parse "pipeline/123/stage/456/job"
    # Implementation here
  end
end
```

### Value Objects

Classes that represent values without identity, often embedded in persistent entities:

| GoCD Class | Purpose | Elixir Representation | Storage |
|---|---|---|---|
| `BuildCause` | Why pipeline was triggered | `map` | Stored as JSONB in `pipeline_instances.build_cause` |
| `MaterialRevisions` | Collection of material changes | `list of maps` | Part of BuildCause JSON |
| `EnvironmentVariables` | Key-value pairs | `map` | Stored as JSONB in various `_config` tables |
| `JobStateTransitions` | State change history | `list of maps` | Not persisted separately (calculated) |
| `Resources` | Agent resources | `list of strings` | Stored as array in `jobs.resources` |

**BuildCause Implementation:**
```elixir
defmodule ExGoCD.Domain.BuildCause do
  @moduledoc """
  Represents why a pipeline was triggered and what revisions it contains.
  Value object - not persisted separately, stored as JSON in pipeline_instances.
  Based on: domain/buildcause/BuildCause.java
  """
  defstruct [
    :material_revisions,
    :approver,
    :trigger_message,
    :trigger_forced,
    :variables
  ]

  @type t :: %__MODULE__{
    material_revisions: [map()],
    approver: String.t(),
    trigger_message: String.t(),
    trigger_forced: boolean(),
    variables: map()
  }

  def to_json(%__MODULE__{} = cause) do
    %{
      "material_revisions" => cause.material_revisions,
      "approver" => cause.approver,
      "trigger_message" => cause.trigger_message,
      "trigger_forced" => cause.trigger_forced,
      "variables" => cause.variables
    }
  end

  def from_json(json) when is_map(json) do
    %__MODULE__{
      material_revisions: json["material_revisions"] || [],
      approver: json["approver"],
      trigger_message: json["trigger_message"],
      trigger_forced: json["trigger_forced"] || false,
      variables: json["variables"] || %{}
    }
  end
end
```

### Collections

GoCD has collection classes that wrap lists with domain logic:

| GoCD Class | Purpose | Elixir Representation | Notes |
|---|---|---|---|---|
| `JobInstances` | Collection of JobInstance | `list` + module functions | Use `ExGoCD.Pipelines.JobInstances` module |
| `Stages` | Collection of Stage | `list` + module functions | Use `ExGoCD.Pipelines.Stages` module |
| `Materials` | Collection of materials | `list` + module functions | Use `ExGoCD.Pipelines.Materials` module |

**Collection Module Pattern:**
```elixir
defmodule ExGoCD.Pipelines.JobInstances do
  @moduledoc """
  Functions for working with collections of job instances.
  Based on: domain/JobInstances.java
  """

  alias ExGoCD.Pipelines.JobInstance

  @doc "Calculate overall stage state from job states"
  def stage_state(job_instances) when is_list(job_instances) do
    cond do
      Enum.any?(job_instances, &building?/1) -> "Building"
      Enum.all?(job_instances, &passed?/1) -> "Passed"
      Enum.any?(job_instances, &failed?/1) -> "Failed"
      true -> "Unknown"
    end
  end

  defp building?(%JobInstance{state: "Building"}), do: true
  defp building?(_), do: false

  defp passed?(%JobInstance{result: "Passed"}), do: true
  defp passed?(_), do: false

  defp failed?(%JobInstance{result: "Failed"}), do: true
  defp failed?(_), do: false
end
```

## Current Schema Status

### Correctly Using Ecto Schemas ✅

- `ExGoCD.Pipelines.Pipeline` (PipelineConfig)
- `ExGoCD.Pipelines.Stage` (StageConfig)
- `ExGoCD.Pipelines.Job` (JobConfig)
- `ExGoCD.Pipelines.Task` (Task configs)
- `ExGoCD.Pipelines.Material` (Material configs)
- `ExGoCD.Pipelines.PipelineInstance` (Pipeline execution)
- `ExGoCD.Pipelines.StageInstance` (Stage execution)
- `ExGoCD.Pipelines.JobInstance` (Job execution)

### Should Be Structs (NOT Ecto Schemas) ❌

Need to create these as plain Elixir structs:

- `ExGoCD.Domain.BuildCause` - Currently stored as map in `pipeline_instances.build_cause`
- `ExGoCD.Domain.JobIdentifier` - Currently stored as string in `job_instances.identifier`
- `ExGoCD.Domain.StageIdentifier` - Currently stored as string in `stage_instances.identifier`
- Collection modules: `JobInstances`, `Stages`, `Materials` (functions, not schemas)

## Implementation Plan

1. **Create struct modules** in `lib/ex_gocd/domain/`:
   - `build_cause.ex`
   - `job_identifier.ex`
   - `stage_identifier.ex`
   - `pipeline_identifier.ex`

2. **Create collection modules** in `lib/ex_gocd/pipelines/`:
   - `job_instances.ex` (collection functions)
   - `stages.ex` (collection functions)
   - `materials.ex` (collection functions)

3. **Update schemas** to use these structs:
   - `PipelineInstance.build_cause` - add casting from/to BuildCause struct
   - `JobInstance.identifier` - add casting from/to JobIdentifier struct
   - `StageInstance.identifier` - add casting from/to StageIdentifier struct

4. **Update tests** to use struct-based fixtures

## References

- GoCD Source: `domain/buildcause/BuildCause.java`
- GoCD Source: `domain/JobIdentifier.java`
- GoCD Source: `domain/StageIdentifier.java`
- GoCD Source: `domain/JobInstances.java`
- GoCD Source: `domain/Stages.java`

## Benefits

1. **Type Safety**: Structs provide compile-time guarantees
2. **Performance**: No unnecessary database overhead
3. **Clarity**: Clear separation between persistent and transient objects
4. **GoCD Alignment**: Matches GoCD's architecture exactly
5. **Testability**: Easier to test pure functions on structs
