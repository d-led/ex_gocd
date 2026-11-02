defmodule ExGoCD.PipelineGraph do
  @moduledoc """
  A pipeline is not a line of stages — it is a node in a graph, and the shapes
  GoCD gives that graph names are worth having:

    * **fan-out** — one material, several pipelines. When the upstream finishes,
      everything downstream that depends on it starts.
    * **fan-in** — several upstreams, one pipeline. It waits for all of them, so
      a deploy cannot start because UAT went green while staging was still
      running.
    * **passing results** — a job publishes an artifact; a `fetch` task in another
      pipeline takes it, instead of building it again.
    * **build once** — the four together: one pipeline builds the artifact, the
      deploy pipelines fetch that same build. What is deployed is what was
      tested, which is the whole point of a CD server.

  A graph is also where the mistakes are structural, and structural mistakes are
  the ones a machine can find before anything runs: a cycle, a dependency on a
  pipeline nobody declares, a fetch of an artifact nobody publishes.

  This module answers those, over a graph that does not exist yet (`problems/2`)
  as readily as over the one that does. Whether an agent can take the jobs is
  `ExGoCD.ConfigAudit`'s question — a graph can be shaped perfectly and still
  never run.
  """

  alias ExGoCD.Pipelines

  @type problem :: %{code: atom(), subject: String.t(), message: String.t()}

  @doc """
  The structural problems in a proposed graph, read against what is configured.

  A proposed pipeline may depend on another one in the same call or on a pipeline
  that already exists; a fetch may take an artifact from either. Anything else —
  a dependency that names nothing, a fetch whose source has no such stage, a
  cycle that would never settle — is reported before a single row is written.
  """
  @spec problems([map()], [map()]) :: [problem()]
  def problems(proposed, configured) do
    nodes = nodes(proposed, configured)

    duplicates(proposed) ++
      unknown_upstreams(proposed, nodes) ++ cycles(nodes) ++ fetch_problems(nodes)
  end

  @doc "The same, read against the configuration as it stands."
  @spec problems([map()]) :: [problem()]
  def problems(proposed), do: problems(proposed, Pipelines.list_pipelines())

  # ── the graph ──────────────────────────────────────────────────────

  # Every pipeline becomes one node, whether it is proposed in this call or
  # already stored: the questions are about the graph that would exist, and the
  # stored half is usually where a cycle hides.
  defp nodes(proposed, configured) do
    proposed_nodes =
      Map.new(proposed, fn definition ->
        {definition.name, node(definition.name, definition, true)}
      end)

    configured_nodes =
      Map.new(configured, fn pipeline ->
        {pipeline.name, configured_node(pipeline)}
      end)

    Map.merge(configured_nodes, proposed_nodes)
  end

  defp node(name, definition, proposed?) do
    %{
      name: name,
      proposed?: proposed?,
      upstreams: upstreams(definition.materials || []),
      stages: stage_index(definition.stages || []),
      fetches: fetches(definition.stages || [])
    }
  end

  defp configured_node(pipeline) do
    stages = pipeline.stages || []

    %{
      name: pipeline.name,
      proposed?: false,
      upstreams: upstreams(pipeline.materials || []),
      stages: stage_index(stages),
      fetches: configured_fetches(stages)
    }
  end

  defp upstreams(materials) do
    materials
    |> Enum.filter(&(field(&1, :type) == "dependency"))
    |> Enum.map(&upstream_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp upstream_name(material) do
    Map.get(material, :pipeline) || Map.get(material, "pipeline") || field(material, :url)
  end

  # A proposed material is the map the tool parsed; a stored one is a struct.
  # Both answer to the same questions, spelled the same way.
  defp field(%_{} = struct, key), do: Map.get(struct, key)
  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp stage_index(stages) do
    Map.new(stages, fn stage ->
      jobs = stage.jobs || []

      {stage.name,
       Map.new(jobs, fn job ->
         {job.name, artifacts(job)}
       end)}
    end)
  end

  defp artifacts(job) do
    case Map.get(job, :artifacts) || Map.get(job, "artifacts") do
      artifacts when is_list(artifacts) -> artifacts
      _none -> []
    end
  end

  defp fetches(stages) do
    for stage <- stages,
        job <- stage.jobs || [],
        task <- job.tasks || [],
        task.type == "fetch",
        do: %{
          pipeline: task.pipeline,
          stage: task.stage,
          job: task.job,
          src: task.src,
          from: {"#{stage.name}", job.name}
        }
  end

  # A stored fetch task keeps its coordinates in `arguments`, the shape the
  # scheduler reads: [pipeline, stage, job, src_file, dest].
  defp configured_fetches(stages) do
    for stage <- stages,
        job <- stage.jobs || [],
        task <- job.tasks || [],
        task.type == "fetch",
        [pipeline, stage_name, job_name, src, _dest] <- [task.arguments || []],
        do: %{
          pipeline: pipeline,
          stage: stage_name,
          job: job_name,
          src: src,
          from: {stage.name, job.name}
        }
  end

  # ── the questions ──────────────────────────────────────────────────

  defp duplicates(proposed) do
    proposed
    |> Enum.map(& &1.name)
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} ->
      problem(:duplicate_pipeline, name, "`#{name}` is declared twice in the same graph.")
    end)
  end

  defp unknown_upstreams(proposed, nodes) do
    for definition <- proposed,
        upstream <- upstreams(definition.materials || []),
        not Map.has_key?(nodes, upstream) do
      problem(
        :unknown_upstream,
        definition.name,
        "`#{definition.name}` depends on `#{upstream}`, which is neither in this graph " <>
          "nor configured."
      )
    end
  end

  defp cycles(nodes) do
    nodes
    |> Map.keys()
    |> Enum.reduce({[], MapSet.new()}, fn name, {found, seen} ->
      {path, seen} = walk(name, nodes, [], seen)
      if path, do: {[path | found], seen}, else: {found, seen}
    end)
    |> elem(0)
    |> Enum.uniq()
    |> Enum.map(fn path ->
      problem(
        :cycle,
        Enum.join(path, " -> "),
        "These pipelines depend on each other: #{Enum.join(path ++ [hd(path)], " -> ")}. " <>
          "None of them could ever start first."
      )
    end)
  end

  # Depth-first, remembering the path rather than only the visited set: a cycle
  # is only useful as the list of names that make it.
  defp walk(name, nodes, path, seen) do
    cond do
      name in path ->
        {Enum.drop_while(path, &(&1 != name)) ++ [name], seen}

      MapSet.member?(seen, name) ->
        {nil, seen}

      true ->
        walk_upstreams(
          Map.get(nodes, name, %{upstreams: []}).upstreams,
          nodes,
          path ++ [name],
          MapSet.put(seen, name)
        )
    end
  end

  defp walk_upstreams(upstreams, nodes, path, seen) do
    Enum.reduce_while(upstreams, {nil, seen}, fn upstream, {nil, seen} ->
      case walk(upstream, nodes, path, seen) do
        {nil, seen} -> {:cont, {nil, seen}}
        {path, seen} -> {:halt, {path, seen}}
      end
    end)
  end

  defp fetch_problems(nodes) do
    Enum.flat_map(nodes, fn {name, node} ->
      Enum.flat_map(node.fetches, &fetch_problem(name, &1, nodes))
    end)
  end

  defp fetch_problem(name, fetch, nodes) do
    source = fetch.pipeline || name

    case Map.get(nodes, source) do
      nil ->
        [
          problem(
            :unknown_fetch_source,
            name,
            "`#{name}` fetches from `#{source}`, which is neither in this graph nor configured."
          )
        ]

      node ->
        fetch_target_problems(name, fetch, source, node)
    end
  end

  defp fetch_target_problems(name, fetch, source, node) do
    case fetch_stage(node, fetch, source, name) do
      {:ok, jobs} -> fetch_job_problems(jobs, fetch, source, name)
      {:error, problems} -> problems
    end
  end

  defp fetch_job_problems(jobs, fetch, source, name) do
    case fetch_job(jobs, fetch, source, name) do
      {:ok, artifacts} -> unpublished(name, fetch, source, artifacts)
      {:error, problems} -> problems
    end
  end

  defp fetch_stage(node, fetch, source, name) do
    case Map.fetch(node.stages, fetch.stage) do
      {:ok, jobs} ->
        {:ok, jobs}

      :error ->
        {:error,
         [
           problem(
             :unknown_fetch_stage,
             name,
             "`#{name}` fetches from stage `#{fetch.stage}` of `#{source}`, which has " <>
               "no such stage. It has #{quoted(Map.keys(node.stages))}."
           )
         ]}
    end
  end

  defp fetch_job(jobs, fetch, source, name) do
    case Map.fetch(jobs, fetch.job) do
      {:ok, artifacts} ->
        {:ok, artifacts}

      :error ->
        {:error,
         [
           problem(
             :unknown_fetch_job,
             name,
             "`#{name}` fetches from job `#{fetch.job}` of `#{source}`, which has no " <>
               "such job. It has #{quoted(Map.keys(jobs))}."
           )
         ]}
    end
  end

  # Only the unambiguous mistake: a job that publishes nothing cannot be fetched
  # from. Whether a glob covers a particular path is a question only a run can
  # answer, so it is not guessed here.
  defp unpublished(name, fetch, source, []) do
    [
      problem(
        :unpublished_artifact,
        name,
        "`#{name}` fetches `#{fetch.src}` from `#{source}` / `#{fetch.stage}` / " <>
          "`#{fetch.job}`, which publishes no artifacts — there is nothing to take. " <>
          "`gocd_build_once` shows how a build is published."
      )
    ]
  end

  defp unpublished(_name, _fetch, _source, _artifacts), do: []

  # ── words ──────────────────────────────────────────────────────────

  defp quoted([]), do: "nothing"
  defp quoted(names), do: Enum.map_join(names, ", ", &"`#{&1}`")

  defp problem(code, subject, message), do: %{code: code, subject: subject, message: message}
end
