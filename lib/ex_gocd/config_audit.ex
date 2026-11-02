defmodule ExGoCD.ConfigAudit do
  @moduledoc """
  "Will it run?" — asked of the configuration, before anything runs.

  A job runs when some agent can take it, and an agent can take a job when

    * it holds every resource the job asks for (after `\#{parameter}`
      interpolation), and
    * the environments agree. GoCD's rule, from `managing_environments.md`: an
      agent in an environment takes only that environment's pipelines, and a
      pipeline in no environment goes only to agents in no environment.

  That is the question `will_it_go_cd` used to ask of a `server.xml`, printing
  `<<<OOPS>>>` beside the jobs no agent could take. Asked of the server's own
  configuration the answer cannot be stale — and asked about a job described
  rather than stored (`fit/2`) it is the same check an author needs before the
  pipeline exists.

  It answers *can this ever run*, not *why did that one not run*: pause, locks,
  materials, disk space and a silent agent are `ExGoCD.SchedulingChecker`'s
  question, and neither answers whether a run will pass.

  Elastic jobs are left to the elastic scheduler and reported as such rather
  than checked against physical agents — an agent that does not exist yet cannot
  be counted.
  """

  alias ExGoCD.{Agents, Environments, Params, Pipelines}

  @typedoc "An agent, as much of it as the question needs."
  @type agent :: %{
          uuid: String.t() | nil,
          hostname: String.t(),
          resources: [String.t()],
          environments: [String.t()],
          disabled: boolean()
        }

  @typedoc "A job, as much of it as the question needs."
  @type job :: %{
          pipeline: String.t(),
          stage: String.t(),
          job: String.t(),
          resources: [String.t()],
          environments: [String.t()],
          elastic_profile: String.t() | nil,
          tasks: non_neg_integer()
        }

  @type finding :: %{
          code: atom(),
          severity: :error | :warning,
          subject: String.t(),
          message: String.t()
        }

  @doc """
  Every finding about the configuration as it stands, and the counts behind them.

  A job nothing can take is an error: it will queue forever. An agent that can
  take nothing, a job whose only agent is switched off, and a job that names an
  undefined parameter are warnings: they are somebody's intention, half-finished.
  """
  @spec report() :: %{findings: [finding()], summary: map()}
  def report do
    agents = agents()
    pipelines = configured_pipelines()
    environments = pipeline_environments()
    jobs = Enum.flat_map(pipelines, &jobs_of(&1, environments))
    verdicts = Enum.map(jobs, &{&1, fit_agents(agents, &1.resources, &1.environments)})

    findings =
      structural(pipelines) ++
        case Enum.filter(agents, &available?/1) do
          [] ->
            [no_agents(agents)]

          _usable ->
            job_findings(verdicts) ++ Enum.flat_map(agents, &agent_findings(&1, jobs))
        end

    %{
      findings: findings,
      summary: %{
        pipelines: length(pipelines),
        jobs: length(jobs),
        agents: length(agents),
        available_agents: Enum.count(agents, &available?/1),
        jobs_without_an_agent:
          Enum.count(verdicts, fn {job, %{runnable: runnable}} ->
            job.elastic_profile == nil and runnable == []
          end),
        elastic_jobs: Enum.count(jobs, &(&1.elastic_profile != nil)),
        errors: Enum.count(findings, &(&1.severity == :error)),
        warnings: Enum.count(findings, &(&1.severity == :warning))
      }
    }
  end

  @doc """
  Which agents can take a job that asks for `resources` and lives in
  `environments`, and why the others cannot.

  A job that does not exist yet has no environments — and that is itself the most
  useful sentence in the answer: a pipeline in no environment runs only on agents
  in no environment, so a fleet that is entirely inside environments can take
  nothing from it until it is assigned to one.
  """
  @spec fit([String.t()], [String.t()]) :: %{runnable: [agent()], blocked: [map()]}
  def fit(resources, environments) when is_list(resources) and is_list(environments) do
    fit_agents(agents(), resources, environments)
  end

  @doc """
  The same question asked of a fleet the caller names, rather than the configured
  one — enough to ask "could these jobs run at the same time?" about a fleet that
  is not the one storing them.
  """
  @spec fit([String.t()], [String.t()], [agent()]) :: %{runnable: [agent()], blocked: [map()]}
  def fit(resources, environments, agents)
      when is_list(resources) and is_list(environments) and is_list(agents) do
    fit_agents(agents, resources, environments)
  end

  @doc """
  One existing pipeline, job by job: who can take it, and the sentence for it
  when nobody can. `nil` when there is no such pipeline.

  This is what `gocd_create_pipeline` asks the moment a pipeline is built, so a
  definition that nothing can run says so while its author is still there.
  """
  @spec fit_pipeline(String.t()) :: map() | nil
  def fit_pipeline(name) when is_binary(name) do
    case Pipelines.get_pipeline_by_name(name) do
      nil ->
        nil

      pipeline ->
        agents = agents()
        environments = pipeline_environments()
        resolved = Pipelines.resolve_template_stages(pipeline)

        %{
          pipeline: pipeline.name,
          environments: Map.get(environments, pipeline.name, []),
          jobs: Enum.map(jobs_of(resolved, environments), &job_verdict(agents, &1))
        }
    end
  end

  @doc """
  One obstacle as a sentence fragment, for a finding or an answer:
  `it does not have \`docker\``.
  """
  @spec obstacle_text(term()) :: String.t()
  def obstacle_text(:disabled), do: "it is disabled"

  def obstacle_text({:missing_resources, missing}),
    do: "it does not have #{quoted(missing)}"

  def obstacle_text({:environment, {:pipeline_is_in_an_environment, environments}}),
    do: "it is in no environment, and the pipeline is in #{quoted(environments)}"

  def obstacle_text({:environment, {:agent_is_in_an_environment, environments}}),
    do: "it is in #{quoted(environments)} and the pipeline is in no environment"

  def obstacle_text(
        {:environment, {:no_shared_environment, %{agent: agent, pipeline: pipeline}}}
      ),
      do: "it is in #{quoted(agent)} and the pipeline is in #{quoted(pipeline)}"

  # ── the configuration as it stands ─────────────────────────────────

  @doc """
  The agents as these questions need them: their resources, the environments
  they are in, and whether somebody switched them off. A design review asks the
  same questions of a fleet it did not load itself.
  """
  @spec fleet() :: [agent()]
  def fleet, do: agents()

  @doc "Which environments each pipeline belongs to, by pipeline name."
  @spec environments() :: %{String.t() => [String.t()]}
  def environments, do: pipeline_environments()

  defp agents do
    Agents.list_agents()
    |> Enum.map(fn agent ->
      %{
        uuid: agent.uuid,
        hostname: agent.hostname || "agent #{agent.uuid}",
        resources: agent.resources || [],
        environments: agent.environments || [],
        disabled: agent.disabled == true
      }
    end)
  end

  defp pipeline_environments do
    Environments.list_environments()
    |> Enum.flat_map(fn environment ->
      Enum.map(environment.pipelines, &{&1.name, environment.name})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp jobs_of(pipeline, environments) do
    stages = Map.get(pipeline, :stages) || []

    Enum.flat_map(stages, fn stage ->
      Enum.map(stage.jobs, &job_spec(&1, pipeline, stage, environments))
    end)
  end

  # A template's stages belong to the template, so a pipeline that uses one has
  # none of its own; resolving it is the only way to see the jobs it will run.
  defp configured_pipelines do
    Pipelines.list_pipelines()
    |> Enum.map(&Pipelines.resolve_template_stages/1)
  end

  defp job_spec(job, pipeline, stage, environments) do
    params = Params.merge_params(pipeline.parameters, %{})

    %{
      pipeline: pipeline.name,
      stage: stage.name,
      job: job.name,
      resources:
        (job.resources || []) |> Enum.map(&Params.interpolate(&1, params)) |> Enum.uniq(),
      environments: Map.get(environments, pipeline.name, []),
      elastic_profile: job.elastic_profile_id,
      tasks: length(job.tasks || [])
    }
  end

  # ── the question ───────────────────────────────────────────────────

  defp fit_agents(agents, resources, environments) do
    {runnable, blocked} =
      agents
      |> Enum.map(&{&1, obstacles(&1, resources, environments)})
      |> Enum.split_with(fn {_agent, obstacles} -> obstacles == [] end)

    %{
      runnable: Enum.map(runnable, &elem(&1, 0)),
      blocked:
        Enum.map(blocked, fn {agent, obstacles} ->
          %{agent: agent, obstacles: obstacles}
        end)
    }
  end

  defp obstacles(agent, resources, environments) do
    disabled(agent) ++ missing(agent, resources) ++ environment(agent, environments)
  end

  defp disabled(%{disabled: true}), do: [:disabled]
  defp disabled(_agent), do: []

  defp missing(agent, resources) do
    case resources -- agent.resources do
      [] -> []
      missing -> [{:missing_resources, missing}]
    end
  end

  defp environment(agent, environments) do
    case environment_mismatch(agent.environments, environments) do
      nil -> []
      mismatch -> [{:environment, mismatch}]
    end
  end

  defp environment_mismatch([], []), do: nil

  defp environment_mismatch([], environments),
    do: {:pipeline_is_in_an_environment, environments}

  defp environment_mismatch(environments, []),
    do: {:agent_is_in_an_environment, environments}

  defp environment_mismatch(agent, environments) do
    if Enum.any?(agent, &(&1 in environments)) do
      nil
    else
      {:no_shared_environment, %{agent: agent, pipeline: environments}}
    end
  end

  defp available?(agent), do: not agent.disabled

  # ── findings ───────────────────────────────────────────────────────

  defp structural(pipelines) do
    Enum.flat_map(pipelines, fn pipeline ->
      unknown_template(pipeline) ++ no_stages(pipeline)
    end)
  end

  defp unknown_template(%{template_id: nil, template_name: name} = pipeline)
       when is_binary(name) and name != "" do
    [
      finding(
        :error,
        :unknown_template,
        pipeline.name,
        "Pipeline `#{pipeline.name}` uses the template `#{name}`, which does not " <>
          "exist — it has no stages to run."
      )
    ]
  end

  defp unknown_template(_pipeline), do: []

  defp no_stages(pipeline) do
    if pipeline.stages in [nil, []] do
      [
        finding(
          :error,
          :pipeline_without_stages,
          pipeline.name,
          "Pipeline `#{pipeline.name}` has no stages and no template, so it has " <>
            "nothing to run."
        )
      ]
    else
      []
    end
  end

  defp no_agents([]) do
    finding(
      :error,
      :no_agents,
      "every job",
      "No agent is registered, so every job waits forever. Start an agent and it " <>
        "will pick work up on its next ping."
    )
  end

  defp no_agents(agents) do
    finding(
      :error,
      :no_agents,
      "every job",
      "All #{length(agents)} agent(s) are disabled, so every job waits. " <>
        "`gocd_update_agent` enables one."
    )
  end

  defp job_findings(verdicts) do
    Enum.flat_map(verdicts, fn {job, verdict} -> job_findings(job, verdict) end)
  end

  defp job_findings(job, _verdict) when is_binary(job.elastic_profile) do
    undefined_parameters(job) ++ no_tasks(job)
  end

  defp job_findings(job, %{runnable: runnable, blocked: blocked}) do
    undefined_parameters(job) ++ no_tasks(job) ++ runnability(job, runnable, blocked)
  end

  defp undefined_parameters(job) do
    job.resources
    |> Enum.filter(&String.contains?(&1, "\#{"))
    |> Enum.map(fn resource ->
      finding(
        :warning,
        :undefined_parameter,
        subject(job),
        "#{subject(job)} asks for the resource `#{resource}`, but no parameter " <>
          "defines it, so no agent can ever match that name. Define the " <>
          "parameter on the pipeline, or give the job the resource itself."
      )
    end)
  end

  defp no_tasks(job) do
    if job.tasks == 0 do
      [
        finding(
          :error,
          :job_without_tasks,
          subject(job),
          "#{subject(job)} has no tasks: it would pass without doing anything."
        )
      ]
    else
      []
    end
  end

  defp runnability(job, [], [_ | _] = blocked) do
    case Enum.filter(blocked, &(&1.obstacles == [:disabled])) do
      [_ | _] = disabled ->
        [
          finding(
            :warning,
            :only_disabled_agents_can_take_it,
            subject(job),
            "#{subject(job)} can run only on #{agents_named(disabled)}, which " <>
              "#{if length(disabled) == 1, do: "is", else: "are"} disabled. It " <>
              "waits until #{if length(disabled) == 1, do: "that agent is", else: "one is"} " <>
              "enabled."
          )
        ]

      [] ->
        closest = Enum.min_by(blocked, &weight(&1.obstacles))

        [
          finding(
            :error,
            :no_agent_can_take_it,
            subject(job),
            "#{subject(job)} #{asks(job)}can run on no agent. Closest: " <>
              "#{agent_name(closest.agent)}, where " <>
              "#{Enum.map_join(closest.obstacles, ", and ", &obstacle_text/1)}."
          )
        ]
    end
  end

  defp runnability(_job, _runnable, _blocked), do: []

  # A disabled agent is somebody's decision, not a finding.
  defp agent_findings(%{disabled: true}, _jobs), do: []

  defp agent_findings(agent, jobs) do
    takes_something =
      Enum.any?(jobs, fn job ->
        fit_agents([agent], job.resources, job.environments).runnable != []
      end)

    if takes_something do
      []
    else
      [
        finding(
          :warning,
          :agent_takes_no_job,
          agent.hostname,
          "Agent `#{agent.hostname}` can take none of the #{length(jobs)} job(s): it " <>
            "holds #{holds(agent.resources)} and is in #{belongs(agent.environments)}."
        )
      ]
    end
  end

  defp job_verdict(agents, job) do
    %{runnable: runnable, blocked: blocked} = fit_agents(agents, job.resources, job.environments)

    job
    |> Map.take([:pipeline, :stage, :job, :resources, :elastic_profile, :tasks])
    |> Map.merge(%{
      runnable: Enum.map(runnable, & &1.hostname),
      blocked:
        Enum.map(blocked, fn %{agent: agent, obstacles: obstacles} ->
          %{agent: agent.hostname, because: Enum.map(obstacles, &obstacle_text/1)}
        end),
      verdict: verdict(runnable, blocked, job),
      advice: advice(runnable, blocked, job)
    })
  end

  defp verdict(_runnable, _blocked, %{elastic_profile: profile}) when is_binary(profile),
    do: "asks for the elastic profile `#{profile}`: the elastic scheduler provides an agent"

  defp verdict([], [], _job), do: "no agent is registered"

  defp verdict([], blocked, _job) do
    closest = Enum.min_by(blocked, &weight(&1.obstacles))

    "no agent can take it — closest is #{agent_name(closest.agent)}, where " <>
      Enum.map_join(closest.obstacles, ", and ", &obstacle_text/1)
  end

  defp verdict(runnable, _blocked, _job) do
    "#{length(runnable)} agent(s) can take it: #{Enum.map_join(runnable, ", ", & &1.hostname)}"
  end

  # What a person would do about it. `nil` when there is nothing to do.
  defp advice(_runnable, [], _job), do: nil
  defp advice([_ | _], _blocked, _job), do: nil

  defp advice([], blocked, job) do
    obstacles = blocked |> Enum.min_by(&weight(&1.obstacles)) |> Map.get(:obstacles)

    cond do
      job.elastic_profile != nil ->
        nil

      Enum.any?(obstacles, &environment_obstacle?/1) and job.environments == [] ->
        "A pipeline in no environment runs only on agents in no environment: assign " <>
          "it to one, or keep an agent outside every environment."

      Enum.any?(obstacles, &environment_obstacle?/1) ->
        "The pipeline and the agent have to share an environment: put both in one."

      true ->
        "Give the resource to an agent (`gocd_update_agent`), or take it off the job."
    end
  end

  defp environment_obstacle?({:environment, _mismatch}), do: true
  defp environment_obstacle?(_obstacle), do: false

  # ── words ──────────────────────────────────────────────────────────

  defp finding(severity, code, subject, message) do
    %{severity: severity, code: code, subject: subject, message: message}
  end

  defp subject(job), do: "`#{job.pipeline}` / `#{job.stage}` / `#{job.job}`"

  defp asks(%{resources: []}), do: ""
  defp asks(%{resources: resources}), do: "asks for #{quoted(resources)} and "

  defp quoted([]), do: "nothing"
  defp quoted(names), do: Enum.map_join(names, ", ", &"`#{&1}`")

  defp holds([]), do: "no resources"
  defp holds(resources), do: quoted(resources)

  defp belongs([]), do: "no environment"
  defp belongs(environments), do: quoted(environments)

  defp agent_name(agent), do: "`#{agent.hostname}`"

  defp agents_named(blocked), do: blocked |> Enum.map(&agent_name(&1.agent)) |> Enum.join(", ")

  # The agent that is nearest to being able to take the job: the one a person
  # would fix. Missing a resource costs more than being in the wrong environment
  # because an agent's resources are its own, while an environment is a decision
  # about the pipeline.
  defp weight(obstacles) do
    Enum.reduce(obstacles, 0, fn
      {:missing_resources, missing}, weight -> weight + 1 + length(missing)
      _other, weight -> weight + 1
    end)
  end
end
