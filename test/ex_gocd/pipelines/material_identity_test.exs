defmodule ExGoCD.Pipelines.MaterialIdentityTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.Material
  alias ExGoCD.Repo

  @repo_url "https://github.com/example/shared.git"

  describe "create_material_for_pipeline/2" do
    test "keeps the branch of each pipeline watching one repository" do
      {:ok, release} = Pipelines.create_pipeline(%{name: "release", group: "test"})
      {:ok, trunk} = Pipelines.create_pipeline(%{name: "trunk", group: "test"})

      :ok = add_material(release, branch: "release")
      :ok = add_material(trunk, branch: "main")

      assert [%Material{branch: "release"}] = materials_of(release)
      assert [%Material{branch: "main"}] = materials_of(trunk)
    end

    test "stores one material for one repository at one branch, however many pipelines use it" do
      {:ok, first} = Pipelines.create_pipeline(%{name: "first", group: "test"})
      {:ok, second} = Pipelines.create_pipeline(%{name: "second", group: "test"})

      :ok = add_material(first, branch: "main")
      :ok = add_material(second, branch: "main")

      assert Repo.aggregate(Material, :count) == 1
    end

    test "treats a missing branch as its own identity" do
      {:ok, pinned} = Pipelines.create_pipeline(%{name: "pinned", group: "test"})
      {:ok, floating} = Pipelines.create_pipeline(%{name: "floating", group: "test"})

      :ok = add_material(pinned, branch: "main")
      :ok = add_material(floating, branch: nil)

      assert [%Material{branch: "main"}] = materials_of(pinned)
      assert [%Material{branch: nil}] = materials_of(floating)
    end
  end

  defp add_material(pipeline, branch: branch) do
    {:ok, _material} =
      Pipelines.create_material_for_pipeline(pipeline, %{
        type: "git",
        url: @repo_url,
        branch: branch,
        name: "shared"
      })

    :ok
  end

  defp materials_of(pipeline) do
    Repo.preload(pipeline, :materials).materials
  end
end
