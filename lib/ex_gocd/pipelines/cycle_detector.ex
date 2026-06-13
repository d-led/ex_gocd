defmodule ExGoCD.Pipelines.CycleDetector do
  @moduledoc """
  Detects circular dependencies in the pipeline graph.
  """
  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Repo

  @doc """
  Checks the entire pipeline graph for cycles and missing dependencies.
  Returns:
    - `:ok` if the graph is acyclic and all dependencies are valid.
    - `{:error, {:circular_dependency, path}}` if a cycle is detected.
    - `{:error, {:missing_pipeline, name}}` if a dependency refers to a non-existent pipeline.
  """
  @spec check_dependency_cycles() ::
          :ok
          | {:error, {:circular_dependency, [String.t()]}}
          | {:error, {:missing_pipeline, String.t()}}
  def check_dependency_cycles do
    pipelines = Repo.all(Pipeline) |> Repo.preload(:materials)
    pipeline_names = MapSet.new(Enum.map(pipelines, & &1.name))

    # Build graph: pipeline_name => list of upstream pipeline names
    graph =
      Enum.reduce(pipelines, %{}, fn p, acc ->
        upstreams =
          p.materials
          |> Enum.filter(&(&1.type == "dependency"))
          |> Enum.map(& &1.url)

        Map.put(acc, p.name, upstreams)
      end)

    # Check for missing pipelines
    missing_ref =
      Enum.find_value(graph, nil, fn {p_name, upstreams} ->
        Enum.find(upstreams, fn target ->
          not MapSet.member?(pipeline_names, target)
        end)
        |> case do
          nil -> nil
          target -> {p_name, target}
        end
      end)

    case missing_ref do
      {_p_name, target} ->
        {:error, {:missing_pipeline, target}}

      nil ->
        find_cycle(graph)
    end
  end

  @spec find_cycle(map()) ::
          :ok | {:error, {:circular_dependency, [String.t()]}}
  defp find_cycle(graph) do
    nodes = Map.keys(graph)

    Enum.reduce_while(nodes, {:ok, MapSet.new()}, fn node, {:ok, visited} ->
      case dfs(node, graph, [], visited) do
        {:ok, new_visited} -> {:cont, {:ok, new_visited}}
        {:error, path} -> {:halt, {:error, path}}
      end
    end)
    |> case do
      {:ok, _visited} -> :ok
      {:error, path} -> {:error, {:circular_dependency, path}}
    end
  end

  @spec dfs(String.t(), map(), [String.t()], MapSet.t()) ::
          {:ok, MapSet.t()} | {:error, [String.t()]}
  defp dfs(node, graph, stack, visited) do
    cond do
      node in stack ->
        # Cycle detected!
        # Reconstruct path from the oldest instance of node in stack, through descendants, back to node.
        # e.g., if node is "A" and stack is ["C", "B", "A"] (meaning A -> B -> C -> A),
        # take_while on stack gives ["C", "B"]. Reverse gives ["B", "C"].
        # Path is ["A", "B", "C", "A"].
        cycle = Enum.reverse(Enum.take_while(stack, &(&1 != node)))
        {:error, [node | cycle] ++ [node]}

      MapSet.member?(visited, node) ->
        {:ok, visited}

      true ->
        traverse_upstreams(Map.get(graph, node, []), graph, [node | stack], visited, node)
    end
  end

  defp traverse_upstreams(upstreams, graph, stack, visited, node) do
    Enum.reduce_while(upstreams, {:ok, visited}, fn next_node, {:ok, vis} ->
      case dfs(next_node, graph, stack, vis) do
        {:ok, updated_vis} -> {:cont, {:ok, updated_vis}}
        {:error, path} -> {:halt, {:error, path}}
      end
    end)
    |> case do
      {:ok, updated_vis} -> {:ok, MapSet.put(updated_vis, node)}
      {:error, path} -> {:error, path}
    end
  end
end
