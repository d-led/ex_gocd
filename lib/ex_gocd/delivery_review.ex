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

  @principles %{
    build_once: "Build once",
    fast_feedback: "Fast feedback",
    parallel_feedback: "Parallel feedback",
    as_code: "As code",
    clean_environment: "Clean environment"
  }

  @doc "The principle labels, for grouping an answer."
  @spec principles() :: %{atom() => String.t()}
  def principles, do: @principles

  @doc """
  Reviews pipelines described as definitions, or configured pipelines, or both.

  Definitions are what `gocd_create_pipeline` reads; configured pipelines are the
  rows, and only those can be judged on living in version control — a definition
  about to be created is code by definition, and a row that no config repository
  owns is a button press somebody made.
  """
  @spec review([map()], [map()]) :: [finding()]
  def review(definitions, configured) do
    views = Enum.map(configured, &configured_view/1) ++ Enum.map(definitions, &definition_view/1)

    findings =
      Enum.flat_map(views, fn view ->
        build_once(view, views) ++
          fast_feedback(view) ++
          parallel_feedback(view) ++
          as_code(view) ++
          clean_environment(view)
      end)

    findings ++ publishes_nothing(views)
  end

  @doc "The same, over the configuration as it stands."
  @spec review() :: [finding()]
  def review, do: review([], ExGoCD.Pipelines.list_pipelines())

  # ── the views ──────────────────────────────────────────────────────

  defp definition_view(definition) do
    %{
      name: definition.name,
      as_code?: true,
      materials: materials(definition.materials || []),
      stages: Enum.map(definition.stages || [], &stage_view/1)
    }
  end

  defp configured_view(pipeline) do
    %{
      name: pipeline.name,
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
  defp parallel_feedback(view) do
    for stage <- view.stages,
        [job] <- [stage.jobs],
        tasks = Enum.count(job.tasks, &(&1.type == "exec")),
        tasks >= 3 do
      finding(
        :parallel_feedback,
        :serial_tasks,
        view.name,
        "`#{view.name}` / `#{stage.name}` / `#{job.name}` runs #{tasks} commands one " <>
          "after another. Tasks are serial by definition, jobs are not: as #{tasks} " <>
          "jobs of one task each they run at the same time on different agents."
      )
    end
  end

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
