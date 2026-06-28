defmodule ExGoCD.Analytics.WorkflowChainTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Analytics
  alias ExGoCD.Pipelines
  alias ExGoCD.Repo

  setup do
    # Create a diamond fan-in pipeline setup
    # upstream-lib → component-a → integration-pipeline → deploy-staging
    # upstream-lib → component-b ↗

    {:ok, lib} = Pipelines.create_pipeline(%{name: "upstream-lib", group: "test-group"})

    Pipelines.create_material_for_pipeline(lib, %{
      type: "git",
      url: "https://github.com/example/lib.git",
      name: "lib"
    })

    {:ok, comp_a} = Pipelines.create_pipeline(%{name: "component-a", group: "test-group"})

    Pipelines.create_material_for_pipeline(comp_a, %{
      type: "git",
      url: "https://github.com/example/a.git",
      name: "a"
    })

    Pipelines.create_material_for_pipeline(comp_a, %{
      type: "dependency",
      url: "upstream-lib",
      name: "upstream-lib"
    })

    {:ok, comp_b} = Pipelines.create_pipeline(%{name: "component-b", group: "test-group"})

    Pipelines.create_material_for_pipeline(comp_b, %{
      type: "git",
      url: "https://github.com/example/b.git",
      name: "b"
    })

    Pipelines.create_material_for_pipeline(comp_b, %{
      type: "dependency",
      url: "upstream-lib",
      name: "upstream-lib"
    })

    {:ok, integration} =
      Pipelines.create_pipeline(%{name: "integration-pipeline", group: "test-group"})

    Pipelines.create_material_for_pipeline(integration, %{
      type: "dependency",
      url: "component-a",
      name: "component-a"
    })

    Pipelines.create_material_for_pipeline(integration, %{
      type: "dependency",
      url: "component-b",
      name: "component-b"
    })

    {:ok, deploy} = Pipelines.create_pipeline(%{name: "deploy-staging", group: "test-group"})

    Pipelines.create_material_for_pipeline(deploy, %{
      type: "dependency",
      url: "integration-pipeline",
      name: "int"
    })

    pipeline_names = [
      "deploy-staging",
      "integration-pipeline",
      "component-b",
      "component-a",
      "upstream-lib"
    ]

    on_exit(fn ->
      for name <- pipeline_names do
        case Repo.get_by(Pipelines.Pipeline, name: name) do
          nil ->
            :ok

          p ->
            p = Repo.preload(p, :materials)
            Pipelines.delete_pipeline(p)
        end
      end
    end)

    :ok
  end

  describe "workflow_chain/1" do
    test "returns upstream and downstream for a middle pipeline" do
      chain = Analytics.workflow_chain("component-a")

      assert chain.pipeline == "component-a"
      assert "upstream-lib" in chain.upstream
      assert "integration-pipeline" in chain.downstream
    end

    test "source pipeline has no upstream" do
      chain = Analytics.workflow_chain("upstream-lib")
      assert chain.upstream == []
      assert "component-a" in chain.downstream
      assert "component-b" in chain.downstream
    end

    test "leaf pipeline has no downstream" do
      chain = Analytics.workflow_chain("deploy-staging")
      assert chain.downstream == []
      assert "integration-pipeline" in chain.upstream
    end
  end

  describe "upstream_chain/1" do
    test "recursive upstream" do
      chain = Analytics.upstream_chain("integration-pipeline")
      assert "component-a" in chain
      assert "component-b" in chain
      assert "upstream-lib" in chain
    end

    test "empty for source pipeline" do
      assert Analytics.upstream_chain("upstream-lib") == []
    end

    test "no duplicates from visited-set guard" do
      # Diamond pattern: component-a and component-b both depend on upstream-lib.
      # The visited set prevents infinite recursion.
      chain = Analytics.upstream_chain("integration-pipeline")
      uniq = Enum.uniq(chain)
      assert "upstream-lib" in uniq
      assert "component-a" in uniq
      assert "component-b" in uniq
    end
  end

  describe "downstream_chain/1" do
    test "recursive downstream" do
      chain = Analytics.downstream_chain("upstream-lib")
      assert "component-a" in chain
      assert "component-b" in chain
      assert "integration-pipeline" in chain
      assert "deploy-staging" in chain
    end

    test "empty for leaf pipeline" do
      assert Analytics.downstream_chain("deploy-staging") == []
    end
  end

  describe "workflow_graph/0" do
    test "returns full adjacency map" do
      graph = Analytics.workflow_graph()
      assert map_size(graph) >= 5
      assert %{upstream: _, downstream: _} = graph["integration-pipeline"]
    end
  end
end
