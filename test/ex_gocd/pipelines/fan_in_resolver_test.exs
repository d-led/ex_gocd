defmodule ExGoCD.Pipelines.FanInResolverTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.FanInResolver
  alias ExGoCD.Pipelines.Material
  alias ExGoCD.Repo

  import ExGoCD.PipelinesFixtures,
    only: [
      insert_pipeline: 1,
      insert_material: 3,
      insert_modification: 2,
      insert_pipeline_instance: 2,
      insert_pmr: 5
    ]

  defp add_material_to_pipeline(pipeline, material) do
    ExGoCD.Pipelines.add_material_to_pipeline(pipeline, material)
  end

  describe "verify_consistency/1" do
    test "always consistent for a single SCM material" do
      # Setup a single pipeline config with a git material
      pipeline = insert_pipeline("pipe-a")
      git_mat = insert_material(pipeline, "git", "http://github.com/test/repo")
      mod = insert_modification(git_mat, "rev-1")

      proposed = %{git_mat.id => {:git, mod}}
      assert FanInResolver.verify_consistency(proposed) == :ok
    end

    test "consistent when all fanned-in paths use the same SCM revision" do
      %{
        git_mat: git_mat,
        pipe_b: pipe_b,
        mod_g1: mod_g1,
        pi_a1: pi_a1,
        mat_a: mat_a,
        mat_b: mat_b
      } =
        setup_fan_in_scenario()

      # B run 1 resolves to same revision of G: g-rev-1
      pi_b1 = insert_pipeline_instance(pipe_b, 1)
      insert_pmr(pi_b1.id, git_mat.id, mod_g1.id, nil, "g-rev-1")

      # Propose triggering C using A/1 and B/1
      proposed = %{mat_a.id => {:pipeline, pi_a1.id}, mat_b.id => {:pipeline, pi_b1.id}}
      assert FanInResolver.verify_consistency(proposed) == :ok
    end

    test "inconsistent when fanned-in paths resolve to different SCM revisions" do
      %{git_mat: git_mat, pipe_b: pipe_b, pi_a1: pi_a1, mat_a: mat_a, mat_b: mat_b} =
        setup_fan_in_scenario()

      # B run 1 resolves to a different revision of G: g-rev-2
      mod_g2 = insert_modification(git_mat, "g-rev-2")
      pi_b1 = insert_pipeline_instance(pipe_b, 1)
      insert_pmr(pi_b1.id, git_mat.id, mod_g2.id, nil, "g-rev-2")

      # Propose triggering C using A/1 and B/1
      proposed = %{mat_a.id => {:pipeline, pi_a1.id}, mat_b.id => {:pipeline, pi_b1.id}}

      assert {:error, {:fan_in_mismatch, matched_id, revs}} =
               FanInResolver.verify_consistency(proposed)

      assert matched_id == git_mat.id
      assert "g-rev-1" in revs
      assert "g-rev-2" in revs
    end

    test "resolves transitive dependencies down to root SCM materials" do
      git_mat = Repo.insert!(%Material{type: "git", url: "git-g"})

      # A depends on G
      pipe_a = insert_pipeline("pipe-a")
      _ = add_material_to_pipeline(pipe_a, git_mat)
      mod_g1 = insert_modification(git_mat, "g-rev-1")

      pi_a1 = insert_pipeline_instance(pipe_a, 1)
      insert_pmr(pi_a1.id, git_mat.id, mod_g1.id, nil, "g-rev-1")

      # B depends on A
      pipe_b = insert_pipeline("pipe-b")
      mat_a_for_b = insert_material(pipe_b, "dependency", "pipe-a")

      # Trigger B run 1 pointing to A/1
      pi_b1 = insert_pipeline_instance(pipe_b, 1)
      insert_pmr(pi_b1.id, mat_a_for_b.id, nil, pi_a1.id, "pipe-a/1")

      # C depends on B and G directly
      pipe_c = insert_pipeline("pipe-c")
      mat_b_for_c = insert_material(pipe_c, "dependency", "pipe-b")
      _ = add_material_to_pipeline(pipe_c, git_mat)

      # Proposed: C triggered with B/1 and G revision "g-rev-2" (inconsistent!)
      mod_g2 = insert_modification(git_mat, "g-rev-2")

      proposed_inconsistent = %{
        mat_b_for_c.id => {:pipeline, pi_b1.id},
        git_mat.id => {:git, mod_g2}
      }

      assert {:error, {:fan_in_mismatch, matched_id, _}} =
               FanInResolver.verify_consistency(proposed_inconsistent)

      assert matched_id == git_mat.id

      # Proposed: C triggered with B/1 and G revision "g-rev-1" (consistent!)
      proposed_consistent = %{
        mat_b_for_c.id => {:pipeline, pi_b1.id},
        git_mat.id => {:git, mod_g1}
      }

      assert FanInResolver.verify_consistency(proposed_consistent) == :ok
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp setup_fan_in_scenario do
    git_mat = Repo.insert!(%Material{type: "git", url: "git-g"})

    pipe_a = insert_pipeline("pipe-a")
    _ = add_material_to_pipeline(pipe_a, git_mat)
    mod_g1 = insert_modification(git_mat, "g-rev-1")
    pi_a1 = insert_pipeline_instance(pipe_a, 1)
    insert_pmr(pi_a1.id, git_mat.id, mod_g1.id, nil, "g-rev-1")

    pipe_b = insert_pipeline("pipe-b")
    _ = add_material_to_pipeline(pipe_b, git_mat)

    pipe_c = insert_pipeline("pipe-c")
    mat_a = insert_material(pipe_c, "dependency", "pipe-a")
    mat_b = insert_material(pipe_c, "dependency", "pipe-b")

    %{git_mat: git_mat, pipe_b: pipe_b, mod_g1: mod_g1, pi_a1: pi_a1, mat_a: mat_a, mat_b: mat_b}
  end
end
