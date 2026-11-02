defmodule ExGoCD.Mcp.Tools.Audit do
  @moduledoc """
  "Will it run?" — asked of the configuration rather than of a run.

  A job waits forever for one of two ordinary reasons: no agent holds a resource
  it asks for, or the environments do not line up. `will_it_go_cd` used to answer
  this from a `server.xml`, printing `<<<OOPS>>>` beside the jobs it found. Asked
  here, the configuration is the server's own and cannot be stale — and
  `gocd_validate_pipeline` asks it of a pipeline that does not exist yet, which
  is the only moment the answer costs nothing.

  It does not answer whether a run will pass; nothing static can.
  """

  alias ExGoCD.{ConfigAudit, PipelineGraph}
  alias ExGoCD.Mcp.{Args, Render, Tool}
  alias ExGoCD.Mcp.Tools.PipelineConfig

  @names ~w(gocd_audit_config gocd_who_can_run gocd_validate_pipeline)

  @tools [
    %{
      "name" => "gocd_audit_config",
      "title" => "Will it run? Audit the configuration",
      "description" =>
        "Reports the configuration's own dead ends: jobs no agent can take (they queue " <>
          "forever), agents that can take none, jobs whose only possible agent is " <>
          "disabled, pipelines whose template is missing, and jobs asking for a resource " <>
          "that an undefined parameter was supposed to fill. Writes nothing. " <>
          "`gocd_who_can_run` explains one pipeline in detail.",
      "inputSchema" => %{"type" => "object", "properties" => %{}},
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_who_can_run",
      "title" => "Who can run this pipeline?",
      "description" =>
        "Job by job: which agents can take it, and for the ones nobody can, which " <>
          "agent came closest and what it lacks. The environment rule is the surprise " <>
          "worth knowing — an agent inside an environment takes only that environment's " <>
          "pipelines, and a pipeline in no environment takes only agents in none. " <>
          "`stage` and `job` narrow the answer to one of them.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pipeline" => %{"type" => "string", "description" => "The pipeline's name."},
          "stage" => %{"type" => "string", "description" => "Only this stage."},
          "job" => %{"type" => "string", "description" => "Only this job."}
        },
        "required" => ["pipeline"]
      },
      "annotations" => Tool.read_only()
    },
    %{
      "name" => "gocd_validate_pipeline",
      "title" => "Check a pipeline definition before creating it",
      "description" =>
        "Reads a definition exactly as `gocd_create_pipeline` would and creates nothing: " <>
          "answers whether it is well formed, whether the graph holds together (a cycle, " <>
          "a dependency nobody declares, a fetch of an artifact nobody publishes), and " <>
          "whether any agent could run its jobs. One pipeline through `definition`, a " <>
          "graph through `pipelines`. A definition wrong in the ninth job costs a " <>
          "sentence here instead of a queue that never moves.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "definition" => PipelineConfig.definition_schema(),
          "pipelines" => %{
            "type" => "array",
            "description" => "A graph: several pipelines in one call, in any order.",
            "items" => PipelineConfig.definition_schema()
          }
        }
      },
      "annotations" => Tool.read_only()
    }
  ]

  @doc "The definitions of this family's tools."
  @spec definitions() :: [map()]
  def definitions, do: @tools

  @doc "The names of this family's tools."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "Whether this family answers to a tool name."
  @spec handles?(String.t()) :: boolean()
  def handles?(name), do: name in @names

  @doc "Calls one of this family's tools."
  @spec call(String.t(), map(), Tool.ctx()) :: Tool.result() | :unknown_tool
  def call("gocd_audit_config", args, ctx), do: audit(args, ctx)
  def call("gocd_who_can_run", args, ctx), do: who_can_run(args, ctx)
  def call("gocd_validate_pipeline", args, ctx), do: validate_pipeline(args, ctx)
  def call(_name, _args, _ctx), do: :unknown_tool

  # ── the whole configuration ────────────────────────────────────────

  defp audit(_args, _ctx) do
    %{findings: findings, summary: summary} = ConfigAudit.report()

    Tool.ok(audit_text(findings, summary), %{
      "summary" => stringify(summary),
      "findings" =>
        Enum.map(findings, fn finding ->
          finding |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
        end)
    })
  end

  defp audit_text([], summary) do
    "Nothing to report. #{counts(summary)} Every job has an agent that can take it."
  end

  defp audit_text(findings, summary) do
    [
      counts(summary),
      section("Will not run", Enum.filter(findings, &(&1.severity == :error))),
      section("Worth a look", Enum.filter(findings, &(&1.severity == :warning)))
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp counts(summary) do
    elastic =
      case summary.elastic_jobs do
        0 ->
          ""

        count ->
          " #{count} of the jobs ask for an elastic profile; the elastic scheduler owns those."
      end

    "#{summary.pipelines} pipeline(s), #{summary.jobs} job(s), " <>
      "#{summary.available_agents} of #{summary.agents} agent(s) available." <> elastic
  end

  defp section(_title, []), do: ""

  defp section(title, findings),
    do: "#{title} (#{length(findings)}):\n#{Render.bullets(messages(findings))}"

  defp messages(findings), do: Enum.map(findings, & &1.message)

  # ── one pipeline ───────────────────────────────────────────────────

  defp who_can_run(args, _ctx) do
    with {:ok, name} <- Args.required(args, "pipeline"),
         {:ok, stage} <- Args.optional(args, "stage"),
         {:ok, job} <- Args.optional(args, "job") do
      case ConfigAudit.fit_pipeline(name) do
        nil ->
          {:error,
           "Pipeline '#{name}' not found. `gocd_list_pipelines` shows the names there are."}

        fit ->
          jobs = narrow(fit.jobs, stage, job)
          Tool.ok(who_can_run_text(fit, jobs), who_can_run_answer(fit, jobs))
      end
    end
  end

  defp narrow(jobs, nil, nil), do: jobs
  defp narrow(jobs, stage, nil), do: Enum.filter(jobs, &(&1.stage == stage))
  defp narrow(jobs, nil, job), do: Enum.filter(jobs, &(&1.job == job))

  defp narrow(jobs, stage, job),
    do: Enum.filter(jobs, &(&1.stage == stage and &1.job == job))

  defp who_can_run_text(%{environments: environments}, []) do
    "No job matches that. #{environment_text(environments)}"
  end

  defp who_can_run_text(fit, jobs) do
    stuck = Enum.reject(jobs, &(&1.runnable != []))

    "#{fit.pipeline}: #{length(jobs) - length(stuck)} of #{length(jobs)} job(s) have an " <>
      "agent. #{environment_text(fit.environments)}\n" <>
      Render.bullets(Enum.map(jobs, &job_line/1)) <>
      advice(stuck)
  end

  defp job_line(job), do: "`#{job.stage}` / `#{job.job}`: #{job.verdict}"

  defp advice([]), do: ""

  defp advice([stuck | _]) do
    case stuck.advice do
      nil -> ""
      advice -> "\n#{advice}"
    end
  end

  defp environment_text([]),
    do: "It is in no environment, so only agents in no environment can take its jobs."

  defp environment_text(environments),
    do:
      "It is in #{quoted(environments)}, so only agents in one of those environments can take its jobs."

  defp who_can_run_answer(fit, jobs) do
    %{
      "pipeline" => fit.pipeline,
      "environments" => fit.environments,
      "jobs" =>
        Enum.map(jobs, fn job ->
          %{
            "stage" => job.stage,
            "job" => job.job,
            "resources" => job.resources,
            "can_run" => job.runnable,
            "cannot_run" =>
              Enum.map(job.blocked, &%{"agent" => &1.agent, "because" => &1.because}),
            "verdict" => job.verdict
          }
        end)
    }
  end

  # ── a definition that does not exist yet ───────────────────────────

  defp validate_pipeline(args, _ctx) do
    with {:ok, definitions} <- PipelineConfig.preview_graph(args) do
      problems = PipelineGraph.problems(definitions)
      verdicts = verdicts(definitions)

      Tool.ok(
        definition_text(definitions, problems, verdicts),
        definition_answer(definitions, problems, verdicts)
      )
    end
  end

  defp verdicts(definitions) do
    for definition <- definitions,
        job <- proposed_jobs(definition),
        do: {definition.name, job, ConfigAudit.fit(job.resources, [])}
  end

  defp proposed_jobs(definition) do
    Enum.flat_map(definition.stages, fn stage ->
      Enum.map(stage.jobs, fn job ->
        %{
          stage: stage.name,
          job: job.name,
          resources: job.resources,
          tasks: length(job.tasks)
        }
      end)
    end)
  end

  defp definition_text(definitions, problems, verdicts) do
    stages = definitions |> Enum.map(&length(&1.stages)) |> Enum.sum()

    body =
      verdicts
      |> Enum.map(fn {pipeline, job, fit} ->
        "`#{pipeline}` / `#{job.stage}` / `#{job.job}`: #{fit_text(fit, job)}"
      end)
      |> Render.bullets()

    "The definition reads: #{length(definitions)} pipeline(s), #{stages} stage(s), " <>
      "#{length(verdicts)} job(s). Nothing was created.\n" <>
      "None of them is in an environment yet, so only agents outside every " <>
      "environment could take their jobs.\n" <>
      body <> problem_text(problems) <> first_advice(verdicts)
  end

  # A graph's structural mistakes are the ones a run cannot recover from, so they
  # come first — an agent fit is worth nothing for a cycle.
  defp problem_text([]), do: ""

  defp problem_text(problems) do
    "\nThe graph itself:\n" <> Render.bullets(Enum.map(problems, & &1.message))
  end

  defp first_advice(verdicts) do
    verdicts
    |> Enum.reject(fn {_pipeline, _job, fit} -> fit.runnable != [] end)
    |> Enum.map(fn {_pipeline, _job, fit} -> fit_advice(fit) end)
    |> Enum.reject(&is_nil/1)
    |> List.first()
    |> case do
      nil -> ""
      advice -> "\n" <> advice
    end
  end

  defp fit_text(%{runnable: [_ | _] = runnable}, _job),
    do:
      "#{length(runnable)} agent(s) can take it: #{Enum.map_join(runnable, ", ", & &1.hostname)}"

  defp fit_text(%{runnable: [], blocked: []}, _job), do: "no agent is registered"

  defp fit_text(%{runnable: [], blocked: blocked}, _job) do
    closest = Enum.min_by(blocked, fn %{obstacles: obstacles} -> length(obstacles) end)

    "no agent can take it — closest is `#{closest.agent.hostname}`, where " <>
      Enum.map_join(closest.obstacles, ", and ", &ConfigAudit.obstacle_text/1)
  end

  defp fit_advice(%{blocked: []}), do: nil

  defp fit_advice(%{blocked: blocked}) do
    closest = Enum.min_by(blocked, fn %{obstacles: obstacles} -> length(obstacles) end)

    if Enum.any?(closest.obstacles, &match?({:environment, _}, &1)) do
      "A pipeline in no environment runs only on agents in no environment: assign it " <>
        "to one when it exists, or keep an agent outside every environment."
    else
      "Give the resource to an agent (`gocd_update_agent`), or take it off the job."
    end
  end

  defp definition_answer(definitions, problems, verdicts) do
    %{
      "pipelines" => Enum.map(definitions, & &1.name),
      "problems" => Enum.map(problems, &%{"code" => to_string(&1.code), "message" => &1.message}),
      "jobs" =>
        Enum.map(verdicts, fn {pipeline, job, fit} ->
          %{
            "pipeline" => pipeline,
            "stage" => job.stage,
            "job" => job.job,
            "resources" => job.resources,
            "can_run" => Enum.map(fit.runnable, & &1.hostname),
            "verdict" => fit_text(fit, job)
          }
        end),
      "will_run" =>
        problems == [] and
          Enum.all?(verdicts, fn {_pipeline, _job, fit} -> fit.runnable != [] end)
    }
  end

  # ── words ──────────────────────────────────────────────────────────

  defp quoted(names), do: Enum.map_join(names, ", ", &"`#{&1}`")

  defp stringify(summary), do: Map.new(summary, fn {key, value} -> {to_string(key), value} end)
end
