defmodule ExGoCD.Pipelines.FanInResolver do
  @moduledoc """
  Implements the Fan-In dependency resolution checks.
  Enforces that multiple paths to a shared SCM material resolve to the exact same revision.
  """
  import Ecto.Query
  alias ExGoCD.Pipelines.Modification
  alias ExGoCD.Pipelines.PipelineInstance
  alias ExGoCD.Pipelines.PipelineMaterialRevision
  alias ExGoCD.Repo

  @doc """
  Verifies if a proposed set of material revisions is consistent.
  `proposed_revisions` is a map of material_id (integer) to:
    - `{:git, revision_string}` (or modification record)
    - `{:pipeline, pipeline_instance_id}` (or pipeline instance record)

  Returns:
    - `:ok` if consistent.
    - `{:error, {:fan_in_mismatch, material_id, list_of_revisions}}` if inconsistent.
  """
  def verify_consistency(proposed_revisions) do
    # Step 1: Collect leaf SCM revisions for each proposed material revision
    scm_resolutions =
      Enum.reduce(proposed_revisions, %{}, fn {material_id, ref}, acc ->
        leafs = resolve_leafs(material_id, ref)
        # Merge leaf resolutions, grouping revisions by material_id
        Map.merge(acc, leafs, fn _key, val1, val2 ->
          List.wrap(val1) ++ List.wrap(val2)
        end)
      end)

    # Step 2: Check for any material_id that has multiple unique revisions
    mismatches =
      Enum.find_value(scm_resolutions, nil, fn {mat_id, revisions} ->
        unique_revisions = Enum.uniq(List.wrap(revisions))
        if length(unique_revisions) > 1 do
          {mat_id, unique_revisions}
        else
          nil
        end
      end)

    case mismatches do
      nil -> :ok
      {mat_id, revs} -> {:error, {:fan_in_mismatch, mat_id, revs}}
    end
  end

  defp resolve_leafs(material_id, {:git, rev}) do
    case rev do
      %Modification{revision: revision} -> %{material_id => [revision]}
      revision when is_binary(revision) -> %{material_id => [revision]}
    end
  end

  defp resolve_leafs(_material_id, {:pipeline, val}) do
    case val do
      %PipelineInstance{id: id} -> get_leaf_scm_revisions(id)
      id when is_integer(id) -> get_leaf_scm_revisions(id)
    end
  end

  defp resolve_leafs(material_id, %Modification{revision: rev}) do
    %{material_id => [rev]}
  end

  defp resolve_leafs(_material_id, %PipelineInstance{id: id}) do
    get_leaf_scm_revisions(id)
  end

  @doc """
  Recursively gets all leaf SCM revisions for a given pipeline instance run.
  """
  def get_leaf_scm_revisions(pipeline_instance_id) do
    pmrs = Repo.all(from pmr in PipelineMaterialRevision, where: pmr.pipeline_instance_id == ^pipeline_instance_id)
    Enum.reduce(pmrs, %{}, &accumulate_leaf_scm/2)
  end

  defp accumulate_leaf_scm(%{parent_pipeline_instance_id: parent_id} = _pmr, acc) when not is_nil(parent_id) do
    upstream = get_leaf_scm_revisions(parent_id)
    Map.merge(acc, upstream, &merge_scm_revisions/3)
  end

  defp accumulate_leaf_scm(pmr, acc) do
    Map.update(acc, pmr.material_id, [pmr.revision], &[pmr.revision | &1])
  end

  defp merge_scm_revisions(_key, val1, val2) do
    List.wrap(val1) ++ List.wrap(val2)
  end
end
