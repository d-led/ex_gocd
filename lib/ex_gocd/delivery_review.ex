defmodule ExGoCD.DeliveryReview do
  @moduledoc """
  The delivery principles, checked against a pipeline or a graph.

  Farley's *Continuous Delivery* — written alongside the Cruise/GoCD team — says
  a deployment pipeline is the definitive statement on whether software is
  releasable: if it passes, the build is safe to release, and that claim is only
  worth something if the pipeline

    * **builds once** — one artifact is built and the same artifact is promoted,
      not rebuilt per environment, because a rebuild is a different binary
      nobody tested;
    * **gives fast feedback** — the cheap verification runs first and runs
      without a human standing in front of it, so a broken commit is known in
      minutes rather than after someone approves a deploy;
    * **tests in parallel** — a stage's jobs run at the same time on different
      agents, while a job's tasks run one after another;
    * **lives in version control** — the topology is code, reviewed with the
      code, not a sequence of button presses on this server;
    * **starts clean** — a stage that unpacks an artifact does so into a
      directory that is not holding the previous run's files.

  Each finding here is one of those, with the fix that follows from it. Every
  check is static — what a pipeline is made of, not what a run did — so this is
  a design review and not a verdict on a build: it cannot say a test suite is
  good, only that the pipeline is arranged so a bad one would be noticed.

  The anti-patterns it names are the mirror image: a deploy that rebuilds, a gate
  where feedback should be, a stage so serialised that feedback is slow by
  construction, and a pipeline that exists nowhere but in one database.
  """

  @type finding :: %{
          principle: atom(),
          code: atom(),
          subject: String.t(),
          message: String.t()
        }

  alias ExGoCD.{ConfigAudit, Pipelines}

  @principles %{
    build_once: "Build once",
    fast_feedback: "Fast feedback",
    parallel_feedback: "Parallel feedback",
    decomposition: "Explicit stages and jobs",
    releasability: "Releasable by the pipeline itself",
    as_code: "As code",
    clean_environment: "Clean environment",
    broken_pipeline: "A red pipeline comes first"
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
          fast_feedback(view) ++
          parallel_feedback(view, context) ++
          decomposition(view) ++
          releasability(view, context) ++
          as_code(view) ++
          clean_environment(view) ++
          broken_pipeline(view)
      end)

    findings ++ publishes_nothing(views) ++ fleet_findings(views, context)
  end

  @doc "The same, about the design only — no fleet, no run history."
  @spec review([map()], [map()]) :: [finding()]
  def review(definitions, configured), do: review(definitions, configured, %{})

  @doc "The same, over the configuration as it stands, with its fleet and its last runs."
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
      as_code?: true,
      materials: materials(definition.materials || []),
      stages: Enum.map(definition.stages || [], &stage_view/1)
    }
  end

  defp configured_view(pipeline) do
    %{
      name: pipeline.name,
      id: pipeline.id,
      as_code?: pipeline.config_repo_id != nil,
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
      approval_type: field(stage, :approval_type) || "success",
      clean?: field(stage, :clean_working_directory) == true,
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
      command: field(task, :command),
      arguments: field(task, :arguments) || [],
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

  # Fast feedback: the first stage should answer "does this build work?" without
  # waiting for a person, and most stages should not wait for one either.
  defp fast_feedback(view) do
    first_stage_gate(view) ++ too_many_gates(view)
  end

  defp first_stage_gate(%{stages: [%{approval_type: "manual"} = stage | _]} = view) do
    [
      finding(
        :fast_feedback,
        :manual_gate_first,
        view.name,
        "`#{view.name}` gates its first stage (`#{stage.name}`) on a person: nothing is " <>
          "built or verified until someone approves, so feedback waits for a human " <>
          "instead of a minute. Gate the stage that deploys, not the one that builds."
      )
    ]
  end

  defp first_stage_gate(_view), do: []

  defp too_many_gates(view) do
    manual = Enum.count(view.stages, &(&1.approval_type == "manual"))

    if manual > 1 and manual * 2 > length(view.stages) do
      [
        finding(
          :fast_feedback,
          :gates_everywhere,
          view.name,
          "#{manual} of #{length(view.stages)} stages in `#{view.name}` need a person. " <>
            "A gate belongs where a release decision is made, not on every step: the " <>
            "rest of the pipeline could have run on its own."
        )
      ]
    else
      []
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

  # A pipeline is not a script with stages drawn around it: the value of splitting
  # the work is that a failure names the part that failed.
  defp decomposition(view) do
    undivided_work(view) ++ shell_one_liners(view)
  end

  # Several commands in one job: they run in sequence, and a failure names the job
  # rather than the step — the two complaints are the same shape, so it is one
  # finding.
  defp undivided_work(view) do
    for stage <- view.stages,
        [job] <- [stage.jobs],
        steps = Enum.count(job.tasks, &(&1.type == "exec")),
        steps >= 2 do
      finding(
        :decomposition,
        :undivided_work,
        view.name,
        "`#{view.name}` is one stage with one job that runs #{steps} commands in " <>
          "sequence: a failure names the job, not the step that broke, and the commands " <>
          "run one after another where #{steps} jobs would run at the same time on " <>
          "different agents."
      )
    end
  end

  defp shell_one_liners(view) do
    for stage <- view.stages, job <- stage.jobs, task <- job.tasks, shell_one_liner?(task) do
      finding(
        :decomposition,
        :shell_one_liner,
        view.name,
        "`#{view.name}` / `#{stage.name}` / `#{job.name}` runs a shell one-liner " <>
          "(`#{Path.basename(task.command)} -c …`): every command inside it is one task " <>
          "as far as the pipeline is concerned, so a failure is an exit code with no " <>
          "name. Make each command a task of its own."
      )
    end
  end

  defp shell_one_liner?(%{type: "exec", command: command, arguments: arguments})
       when is_binary(command) do
    Path.basename(command) in ["sh", "bash", "zsh", "dash", "ksh"] and "-c" in arguments
  end

  defp shell_one_liner?(_task), do: false

  # Releasable by the pipeline itself: a pipeline that ends at a gate leaves the
  # decision, and whatever proves the release good, outside itself.
  defp releasability(view, context) do
    last_stage_gate(view) ++ deploy_without_environment(view, context)
  end

  defp last_stage_gate(%{stages: [_ | _] = stages} = view) do
    case List.last(stages) do
      %{approval_type: "manual"} = stage ->
        [
          finding(
            :releasability,
            :verification_outside_pipeline,
            view.name,
            "`#{view.name}` ends at a gate (`#{stage.name}`): the pipeline stops and a " <>
              "person decides, so whatever proves the release good — a QA regression, a " <>
              "smoke test — happens outside it and leaves no record that it passed. Put " <>
              "that verification in a stage, and passing the pipeline is the release " <>
              "decision."
          )
        ]

      _automatic ->
        []
    end
  end

  defp last_stage_gate(_view), do: []

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
            :releasability,
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

  # A failing pipeline is falsification, not noise: two red runs in a row is the
  # state a team is supposed to treat as the top priority.
  defp broken_pipeline(%{id: nil}), do: []

  defp broken_pipeline(%{id: id} = view) do
    case Pipelines.list_pipeline_instances(id, limit: 2) do
      [latest, previous] ->
        if failed?(latest) and failed?(previous) do
          [
            finding(
              :broken_pipeline,
              :red_twice,
              view.name,
              "`#{view.name}` failed its last two runs (#{latest.counter} and " <>
                "#{previous.counter}). A red pipeline is a statement that the last change " <>
                "is not releasable: fix it or revert it before anything else, or it " <>
                "becomes background noise nobody reads."
            )
          ]
        else
          []
        end

      _fewer ->
        []
    end
  end

  defp failed?(instance), do: Enum.any?(instance.stage_instances || [], &(&1.result == "Failed"))

  defp as_code(view) do
    if view.as_code? do
      []
    else
      [
        finding(
          :as_code,
          :not_in_config_repo,
          view.name,
          "`#{view.name}` is not in a config repository, so it exists only on this " <>
            "server: nobody reviews a change to it, and it is not restored from the " <>
            "code that it builds. Version it with the code."
        )
      ]
    end
  end

  defp clean_environment(view) do
    for stage <- view.stages,
        not stage.clean?,
        Enum.any?(stage.jobs, fn job -> Enum.any?(job.tasks, & &1.fetch) end) do
      finding(
        :clean_environment,
        :dirty_before_fetch,
        view.name,
        "`#{view.name}` / `#{stage.name}` unpacks a fetched artifact into a working " <>
          "directory it does not clean, so the previous run's files are still there " <>
          "and a test can pass on a file nothing rebuilt. Turn on " <>
          "`clean_working_directory` for the stage."
      )
    end
  end

  # ── words ──────────────────────────────────────────────────────────

  defp finding(principle, code, subject, message) do
    %{principle: principle, code: code, subject: subject, message: message}
  end

  defp quoted([]), do: "nothing"
  defp quoted(names), do: Enum.map_join(names, ", ", &"`#{&1}`")

  defp field(%_{} = struct, key), do: Map.get(struct, key)
  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
