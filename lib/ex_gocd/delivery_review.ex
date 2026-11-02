defmodule ExGoCD.DeliveryReview do
  @moduledoc """
  The flow a delivery pipeline has, checked against a pipeline or a graph.

  This review is deliberately narrow: it is about **edges**. What depends on
  what, what is passed along an edge and in which direction, whether an artifact
  a pipeline fetches is one somebody promised to publish, where a pipeline runs,
  and whether the fleet can run the shape its author drew. Those are properties
  of the server's own model — pipelines, materials, artifacts, environments,
  agents — so the server can assert them.

  What a job *does* is not reviewed, and cannot be: a command, a script, a stage
  with one task or with twenty, a gate before or after a stage, and whether the
  configuration lives in a repository are the author's decisions. Judging them
  from the outside would be guessing at intent; the server's job is to make the
  flow correct and to say plainly what it cannot see.

  The three questions it does ask, and the faults behind them:

    * **what passes between pipelines** — a deploy that depends on a build *and*
      checks out the same repository can rebuild what the build already built, so
      what it ships is not the artifact that was tested; a pipeline others
      depend on that publishes no artifacts leaves them nothing to take; a fetch
      from a pipeline that is not a dependency takes whatever that pipeline last
      produced rather than the build this run is for;
    * **the shape the fleet can run** — a stage of jobs that only one agent can
      take is a queue however it is drawn, and a fleet of one agent makes every
      parallel stage serial;
    * **where it runs** — a deploy that belongs to no environment is taken by the
      default pool, with nothing isolating it and no environment to be promoted
      through.

  A finding is a fact about the configuration, never about a run: it can say the
  flow is arranged so that what reaches production is what was tested, and it
  says nothing about whether any of it works.
  """

  @type finding :: %{
          principle: atom(),
          code: atom(),
          subject: String.t(),
          message: String.t()
        }

  alias ExGoCD.{ConfigAudit, Pipelines}

  @principles %{
    build_once: "What passes between pipelines",
    parallel_feedback: "The shape the fleet can run",
    environments: "Where it runs"
  }

  @doc "The principle labels, for grouping an answer."
  @spec principles() :: %{atom() => String.t()}
  def principles, do: @principles

  @doc """
  Reviews pipelines described as definitions, or configured pipelines, or both,
  against a fleet and a run history when the caller has them.

  Definitions are what `gocd_create_pipeline` reads; configured pipelines are the
  rows, and only those can be judged on living in version control or on their last
  runs. `context` carries what a design question needs beyond the text:

    * `:agents` — the fleet, so "these jobs run in parallel" can be checked
      against how many agents can actually take them at once;
    * `:environments` — which pipelines are in which environment, so a deploy
      that belongs to none can be named.

  With no context the review is about the design alone, and the checks that need
  a fleet or a history say nothing rather than guessing.
  """
  @spec review([map()], [map()], map()) :: [finding()]
  def review(definitions, configured, context) do
    views = Enum.map(configured, &configured_view/1) ++ Enum.map(definitions, &definition_view/1)

    findings =
      Enum.flat_map(views, fn view ->
        build_once(view, views) ++
          parallel_feedback(view, context) ++
          deploy_without_environment(view, context)
      end)

    findings ++ publishes_nothing(views) ++ fleet_findings(views, context)
  end

  @doc "The same, about the design only — against no fleet and no stored configuration."
  @spec review([map()], [map()]) :: [finding()]
  def review(definitions, configured), do: review(definitions, configured, %{})

  @doc "The same, over the configuration as it stands, against its own fleet."
  @spec review() :: [finding()]
  def review do
    review([], Pipelines.list_pipelines(), %{
      agents: ConfigAudit.fleet(),
      environments: ConfigAudit.environments()
    })
  end

  # ── the views ──────────────────────────────────────────────────────

  defp definition_view(definition) do
    %{
      name: definition.name,
      id: nil,
      materials: materials(definition.materials || []),
      stages: Enum.map(definition.stages || [], &stage_view/1)
    }
  end

  defp configured_view(pipeline) do
    %{
      name: pipeline.name,
      id: pipeline.id,
      materials: materials(pipeline.materials || []),
      stages: Enum.map(pipeline.stages || [], &stage_view/1)
    }
  end

  defp materials(materials) do
    Enum.map(materials, fn material ->
      %{
        type: field(material, :type),
        url: field(material, :url),
        upstream: upstream_name(material)
      }
    end)
  end

  defp upstream_name(material) do
    (field(material, :type_specific_config) || %{})["pipeline_name"] ||
      field(material, :pipeline) || field(material, :url)
  end

  defp stage_view(stage) do
    %{
      name: stage.name,
      jobs: Enum.map(stage.jobs || [], &job_view/1)
    }
  end

  defp job_view(job) do
    %{
      name: job.name,
      resources: field(job, :resources) || [],
      artifacts: artifacts(job),
      tasks: Enum.map(field(job, :tasks) || [], &task_view/1)
    }
  end

  defp artifacts(job) do
    case field(job, :artifacts) do
      list when is_list(list) -> list
      _none -> field(job, :artifact_configs) |> config_artifacts()
    end
  end

  defp config_artifacts(%{"artifacts" => list}) when is_list(list), do: list
  defp config_artifacts(list) when is_list(list), do: list
  defp config_artifacts(_none), do: []

  defp task_view(task) do
    %{
      type: field(task, :type),
      fetch: fetch_coordinates(task)
    }
  end

  defp fetch_coordinates(%{type: "fetch"} = task) do
    case Map.get(task, :pipeline) do
      nil -> stored_fetch_coordinates(Map.get(task, :arguments) || [])
      pipeline -> %{pipeline: pipeline, stage: Map.get(task, :stage), job: Map.get(task, :job)}
    end
  end

  defp fetch_coordinates(_task), do: nil

  defp stored_fetch_coordinates([pipeline, stage, job, _src, _dest]),
    do: %{pipeline: pipeline, stage: stage, job: job}

  defp stored_fetch_coordinates(_arguments), do: nil

  # ── the principles ─────────────────────────────────────────────────

  # Build once: a deploy that depends on a build and also checks out the same
  # repository can rebuild, and then what it deploys is not what was tested.
  defp build_once(view, views) do
    shares_repository(view, views) ++ fetch_without_dependency(view)
  end

  defp shares_repository(view, views) do
    urls = view |> repositories() |> MapSet.new()

    view
    |> upstreams()
    |> Enum.flat_map(fn upstream ->
      shared = MapSet.intersection(urls, upstream |> repository_of(views) |> MapSet.new())

      if MapSet.size(shared) > 0 do
        [
          finding(
            :build_once,
            :rebuilds_upstream,
            view.name,
            "`#{view.name}` depends on `#{upstream}` and also checks out " <>
              "#{quoted(Enum.sort(shared))}: it can rebuild what `#{upstream}` already " <>
              "built, so what it deploys is not the artifact that was tested. Drop the " <>
              "repository and fetch `#{upstream}`'s artifact instead."
          )
        ]
      else
        []
      end
    end)
  end

  defp upstreams(view),
    do:
      view.materials
      |> Enum.filter(&(&1.type == "dependency"))
      |> Enum.map(&(&1.upstream || &1.url))

  defp repositories(view) do
    view.materials
    |> Enum.reject(&(&1.type == "dependency"))
    |> Enum.map(& &1.url)
    |> Enum.reject(&is_nil/1)
  end

  defp repository_of(name, views) do
    case Enum.find(views, &(&1.name == name)) do
      nil -> []
      upstream -> repositories(upstream)
    end
  end

  defp fetch_without_dependency(view) do
    for fetch <- fetches(view),
        fetch.pipeline,
        fetch.pipeline != view.name,
        fetch.pipeline not in upstreams(view) do
      finding(
        :build_once,
        :fetch_without_dependency,
        view.name,
        "`#{view.name}` fetches from `#{fetch.pipeline}` without depending on it: the " <>
          "fetch picks whatever that pipeline last produced, not the build this run " <>
          "was triggered for. Add it as a dependency material with the stage that " <>
          "produces the artifact."
      )
    end
  end

  defp fetches(view) do
    for stage <- view.stages, job <- stage.jobs, task <- job.tasks, task.fetch, do: task.fetch
  end

  defp published?(view),
    do: view.stages |> Enum.any?(fn stage -> Enum.any?(stage.jobs, &(&1.artifacts != [])) end)

  defp publishes_nothing(views) do
    depended_on = views |> Enum.flat_map(&upstreams/1) |> Enum.uniq()

    for view <- views,
        view.name in depended_on,
        not published?(view) do
      dependents = views |> Enum.filter(&(view.name in upstreams(&1))) |> Enum.map(& &1.name)

      finding(
        :build_once,
        :nothing_to_fetch,
        view.name,
        "`#{view.name}` is depended on by #{quoted(dependents)} and publishes no " <>
          "artifacts, so there is nothing for them to deploy: each of them has to " <>
          "rebuild. Publish what they need as an artifact of this pipeline."
      )
    end
  end

  # Parallel feedback: a stage's jobs run at the same time; a job's tasks do not.
  defp parallel_feedback(view, context) do
    stage_capacity(view, context)
  end

  # Parallel in the design is only parallel in reality when the jobs can be given
  # different agents: a stage of three docker jobs and one agent with docker is a
  # queue with a parallel-looking diagram.
  defp stage_capacity(view, %{agents: [_ | _] = agents} = context) do
    for stage <- view.stages,
        length(stage.jobs) > 1,
        candidates = candidates(stage, view, agents, context),
        Enum.all?(candidates, fn {_job, agents} -> agents != [] end),
        not concurrent?(candidates) do
      finding(
        :parallel_feedback,
        :narrower_than_the_stage,
        view.name,
        "`#{view.name}` / `#{stage.name}` has #{length(stage.jobs)} jobs but at most " <>
          "#{agents_needed(candidates)} agents can take them at the same time, so some " <>
          "of them wait for the others: the stage takes as long as the waves it runs " <>
          "in. Give more agents the resources those jobs ask for (#{resources_text(candidates)})."
      )
    end
  end

  defp stage_capacity(_view, _context), do: []

  defp fleet_findings(views, %{agents: [_] = [agent]}) do
    [
      finding(
        :parallel_feedback,
        :one_agent_fleet,
        "the fleet",
        "The fleet is one agent (`#{agent.hostname}`): every parallel stage in " <>
          "#{length(views)} pipeline(s) is a queue, and the delivery time is the sum " <>
          "of the parts rather than the longest of them."
      )
    ]
  end

  defp fleet_findings(_views, _context), do: []

  defp candidates(stage, view, agents, context) do
    environments = context |> Map.get(:environments, %{}) |> Map.get(view.name, [])

    Enum.map(stage.jobs, fn job ->
      {job, ConfigAudit.fit(job.resources, environments, agents).runnable}
    end)
  end

  # Greedy, smallest candidate set first: exact for the shapes a stage has, and a
  # fair answer to "can these run at once?" without pretending to be a scheduler.
  defp concurrent?(candidates) do
    candidates
    |> Enum.sort_by(fn {_job, agents} -> length(agents) end)
    |> Enum.reduce_while(MapSet.new(), fn {_job, agents}, taken ->
      case Enum.find(agents, &(not MapSet.member?(taken, &1.hostname))) do
        nil -> {:halt, :queued}
        agent -> {:cont, MapSet.put(taken, agent.hostname)}
      end
    end)
    |> then(fn
      :queued -> false
      _taken -> true
    end)
  end

  # The number of agents the stage can actually keep busy at once.
  defp agents_needed(candidates) do
    candidates
    |> Enum.sort_by(fn {_job, agents} -> length(agents) end)
    |> Enum.reduce_while(MapSet.new(), fn {_job, agents}, taken ->
      case Enum.find(agents, &(not MapSet.member?(taken, &1.hostname))) do
        nil -> {:halt, MapSet.size(taken)}
        agent -> {:cont, MapSet.put(taken, agent.hostname)}
      end
    end)
    |> then(fn
      count when is_integer(count) -> count
      taken -> MapSet.size(taken)
    end)
  end

  defp resources_text(candidates) do
    candidates
    |> Enum.flat_map(fn {job, _agents} -> job.resources end)
    |> Enum.uniq()
    |> Enum.sort()
    |> case do
      [] -> "(none)"
      resources -> Enum.map_join(resources, ", ", &"`#{&1}`")
    end
  end

  # Where it runs: a deploy that belongs to no environment is taken by the default
  # pool, which is a statement about the fleet and not about the job's content.
  defp deploy_without_environment(view, %{environments: environments})
       when is_map(environments) do
    cond do
      view.id == nil ->
        []

      upstreams(view) == [] ->
        []

      Map.get(environments, view.name, []) != [] ->
        []

      true ->
        [
          finding(
            :environments,
            :deploy_without_environment,
            view.name,
            "`#{view.name}` deploys but belongs to no environment, so the default pool " <>
              "takes it: nothing isolates it from a build, and it has no environment of " <>
              "its own to be promoted through. Put it in the environment it deploys to."
          )
        ]
    end
  end

  defp deploy_without_environment(_view, _context), do: []

  # ── words ──────────────────────────────────────────────────────────

  defp finding(principle, code, subject, message) do
    %{principle: principle, code: code, subject: subject, message: message}
  end

  defp quoted([]), do: "nothing"
  defp quoted(names), do: Enum.map_join(names, ", ", &"`#{&1}`")

  defp field(%_{} = struct, key), do: Map.get(struct, key)
  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
