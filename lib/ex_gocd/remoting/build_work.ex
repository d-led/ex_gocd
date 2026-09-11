defmodule ExGoCD.Remoting.BuildWork do
  @moduledoc """
  Renders a scheduled job into GoCD's `BuildWork` wire format.

  The official GoCD Java agent asks for work with
  `POST /remoting/api/agent/get_work` and expects a Gson-serialised `Work`
  object whose `type` discriminator is `"BuildWork"`. This module is the single
  place that knows that shape, so the remoting controller stays a thin
  transport and the mapping can be tested against real captured traffic
  (`test/fixtures/remoting/build_work_response.json`).

  Only what the scheduler genuinely knows is emitted. In particular there is no
  `materialRevisions` payload, so `fetchMaterials` is `false`: materials are not
  declared to the agent, and checkout work appears as ordinary exec builders
  because that is how ExGoCD schedules it.
  """

  @job_working_directory_relative_root "pipelines"

  @doc """
  Builds the `BuildWork` map for a scheduled job.

  * `payload` — the work payload the scheduler assigned (internal shape)
  * `run` — the `ExGoCD.AgentJobRuns.AgentJobRun` the payload belongs to
  """
  def render(payload, run) do
    %{
      "type" => "BuildWork",
      "assignment" => assignment(payload, run),
      "consoleLogCharset" => "UTF-8"
    }
  end

  defp assignment(payload, run) do
    working_directory = job_working_directory(run)

    %{
      "fetchMaterials" => false,
      "cleanWorkingDirectory" => false,
      "builders" => builders(payload, working_directory),
      "artifactPlans" => artifact_plans(payload),
      "artifactStores" => [],
      "buildWorkingDirectory" => %{"path" => working_directory},
      "jobIdentifier" => job_identifier(run),
      "initialContext" => %{"properties" => environment_properties(payload, run)},
      "materialRevisions" => %{"revisions" => []},
      "approver" => payload["approver"] || "anonymous"
    }
  end

  @doc """
  The per-job working directory, relative to the agent's own working directory.

  GoCD agents resolve this themselves, so an absolute path from the agent
  record would be wrong on a foreign machine.
  """
  def job_working_directory(run) do
    Enum.join(
      [
        @job_working_directory_relative_root,
        run.pipeline_name,
        run.pipeline_counter,
        run.stage_name,
        run.stage_counter,
        run.job_name
      ],
      "/"
    )
  end

  defp job_identifier(run) do
    %{
      "pipelineName" => run.pipeline_name,
      "pipelineCounter" => run.pipeline_counter,
      "pipelineLabel" => to_string(run.pipeline_counter),
      "stageName" => run.stage_name,
      "stageCounter" => to_string(run.stage_counter),
      "buildName" => run.job_name,
      "buildId" => run.id
    }
  end

  # ── builders ────────────────────────────────────────────────────────────

  defp builders(payload, working_directory) do
    payload
    |> sub_commands()
    |> Enum.filter(&(command_name(&1) == "exec"))
    |> Enum.map(&command_builder(&1, working_directory))
  end

  defp sub_commands(%{"buildCommand" => %{"subCommands" => sub}}) when is_list(sub), do: sub
  defp sub_commands(%{"buildCommand" => %{} = single}), do: [single]
  defp sub_commands(_), do: []

  defp command_name(%{"name" => name}), do: name
  defp command_name(_), do: "exec"

  defp command_builder(%{"command" => command} = cmd, working_directory) do
    args = Map.get(cmd, "args") || []

    %{
      "type" => "CommandBuilderWithArgList",
      "args" => args,
      "command" => command,
      "workingDir" => %{"path" => working_directory},
      "errorString" => "",
      "exitCode" => -1,
      "conditions" => [],
      "description" => Enum.join([command | args], " "),
      "cancelBuilder" => kill_all_child_builder()
    }
  end

  # GoCD's CommandBuilderWithArgList always carries a cancel builder that
  # terminates the child process tree when the job is cancelled.
  defp kill_all_child_builder do
    %{
      "type" => "BuilderForKillAllChildTask",
      "currentProcess" => %{},
      "cancelAttempted" => false,
      "exitCode" => -1,
      "conditions" => [],
      "description" => "Kills child processes",
      "cancelBuilder" => %{
        "type" => "NullBuilder",
        "exitCode" => -1,
        "conditions" => [],
        "description" => "NULL"
      }
    }
  end

  # ── artifacts ───────────────────────────────────────────────────────────

  defp artifact_plans(payload) do
    payload
    |> sub_commands()
    |> Enum.filter(&(command_name(&1) in ["uploadArtifact", "uploadTestArtifact"]))
    |> Enum.map(fn cmd ->
      dest = cmd["dest"] || ""
      src = cmd["src"] || ""

      base = %{
        "type" => if(cmd["type"] == "test", do: "TestArtifactPlan", else: "BuildArtifactPlan"),
        "src" => src,
        "dest" => dest
      }

      Map.put(base, "artifactType", if(cmd["type"] == "test", do: "test", else: "build"))
    end)
  end

  # ── environment ─────────────────────────────────────────────────────────

  defp environment_properties(payload, run) do
    exported =
      payload
      |> sub_commands()
      |> Enum.filter(&(command_name(&1) == "export"))
      |> Enum.map(&export_property/1)

    base = [
      go_property("GO_PIPELINE_NAME", run.pipeline_name),
      go_property("GO_PIPELINE_COUNTER", to_string(run.pipeline_counter)),
      go_property("GO_PIPELINE_LABEL", to_string(run.pipeline_counter)),
      go_property("GO_STAGE_NAME", run.stage_name),
      go_property("GO_STAGE_COUNTER", to_string(run.stage_counter)),
      go_property("GO_JOB_NAME", run.job_name)
    ]

    # Exported variables win over the defaults, and duplicates are collapsed.
    (base ++ exported)
    |> Enum.uniq_by(& &1["name"])
  end

  defp export_property(%{"args" => [name, value], "attributes" => %{"secure" => secure}})
       when is_binary(name) do
    %{
      "name" => name,
      "value" => to_string(value || ""),
      "secure" => secure == true,
      "secretParams" => []
    }
  end

  defp export_property(%{"args" => [name, value]}) when is_binary(name) do
    %{"name" => name, "value" => to_string(value || ""), "secure" => false, "secretParams" => []}
  end

  defp export_property(_), do: nil

  defp go_property(name, value) do
    %{"name" => name, "value" => value, "secure" => false, "secretParams" => []}
  end
end
