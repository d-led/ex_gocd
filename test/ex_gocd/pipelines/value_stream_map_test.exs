defmodule ExGoCD.Pipelines.ValueStreamMapTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.ValueStreamMap

  describe "get_pipeline_vsm/2" do
    test "returns the VSM for a valid mock pipeline" do
      # Given a mock pipeline name and counter
      pipeline_name = "build-linux"
      counter = 1

      # When retrieving its value stream map
      assert {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(pipeline_name, counter)

      # Then the current pipeline is set correctly
      assert vsm["current_pipeline"] == pipeline_name

      # And the levels represent the flow: Upstream Materials -> Target Pipeline -> Downstream
      assert length(vsm["levels"]) >= 2

      # The first level (index 0) contains upstream material nodes
      materials_level = Enum.at(vsm["levels"], 0)
      assert materials_level["nodes"] != []
      for node <- materials_level["nodes"] do
        assert node["node_type"] == "MATERIAL"
        assert node["depth"] == 0
        assert [pipeline_name] == node["dependents"]
      end

      # The second level (index 1) contains the target pipeline node
      target_level = Enum.at(vsm["levels"], 1)
      assert [%{"id" => ^pipeline_name, "node_type" => "PIPELINE", "depth" => 1} = target_node] = target_level["nodes"]
      assert [inst] = target_node["instances"]
      assert inst["counter"] == counter
      assert inst["stages"] != []
    end

    test "returns not_found error for a pipeline that does not exist" do
      # Given an unknown pipeline name
      unknown_pipeline = "unknown-nonexistent-pipeline"

      # When retrieving its value stream map
      # Then it returns a not_found error
      assert {:error, :not_found} = ValueStreamMap.get_pipeline_vsm(unknown_pipeline, 1)
    end
  end

  describe "get_material_vsm/2" do
    test "returns the VSM for a material fingerprint and revision" do
      # Given a material fingerprint and revision
      fingerprint = "8d78bc9f6c661806"
      revision = "abcd1234ef"

      # When retrieving its value stream map
      assert {:ok, vsm} = ValueStreamMap.get_material_vsm(fingerprint, revision)

      # Then the current material is set correctly
      assert vsm["current_material"] == fingerprint

      # And levels contain the material and its downstream dependent pipelines
      assert [material_level | rest_levels] = vsm["levels"]
      assert rest_levels != []
      pipeline_level = hd(rest_levels)

      # The material node is correct
      assert [material_node] = material_level["nodes"]
      assert material_node["id"] == fingerprint
      assert material_node["node_type"] == "MATERIAL"

      # The dependent pipelines are listed under the downstream level
      assert pipeline_level["nodes"] != []
      for pipeline_node <- pipeline_level["nodes"] do
        assert pipeline_node["node_type"] == "PIPELINE"
        assert pipeline_node["depth"] == 1
        assert fingerprint in pipeline_node["parents"]
      end
    end
  end

  describe "get_pipeline_vsm/2 with DB data" do
    setup do
      {:ok, pipeline} =
        %ExGoCD.Pipelines.Pipeline{}
        |> ExGoCD.Pipelines.Pipeline.changeset(%{name: "ci", group: "default", label_template: "${COUNT}"})
        |> ExGoCD.Repo.insert()

      {:ok, mat} =
        %ExGoCD.Pipelines.Material{}
        |> ExGoCD.Pipelines.Material.changeset(%{type: "git", url: "https://github.com/exgocd/ci.git", branch: "main"})
        |> ExGoCD.Repo.insert()

      ExGoCD.Repo.insert_all("pipelines_materials", [%{pipeline_id: pipeline.id, material_id: mat.id}])

      pipeline = ExGoCD.Repo.get(ExGoCD.Pipelines.Pipeline, pipeline.id) |> ExGoCD.Repo.preload(:materials)

      {:ok, stage} =
        %ExGoCD.Pipelines.Stage{}
        |> ExGoCD.Pipelines.Stage.changeset(%{name: "build", pipeline_id: pipeline.id, order_id: 0})
        |> ExGoCD.Repo.insert()

      {:ok, instance} =
        %ExGoCD.Pipelines.PipelineInstance{}
        |> ExGoCD.Pipelines.PipelineInstance.changeset(%{
          pipeline_id: pipeline.id, counter: 4, label: "4", natural_order: 4.0,
          build_cause: %{"materialRevisions" => []}
        })
        |> ExGoCD.Repo.insert()

      completed_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      created_time = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-300, :second)

      {:ok, _stage_instance} =
        %ExGoCD.Pipelines.StageInstance{}
        |> ExGoCD.Pipelines.StageInstance.changeset(%{
          stage_id: stage.id, pipeline_instance_id: instance.id,
          name: "build", counter: 1, order_id: 0, state: "Completed", result: "Passed",
          approval_type: "success", created_time: created_time, completed_at: completed_at
        })
        |> ExGoCD.Repo.insert()

      {:ok, pipeline: pipeline, instance: instance}
    end

    test "renders VSM for a DB pipeline instance", %{pipeline: pipeline} do
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(pipeline.name, 4)
      assert vsm["current_pipeline"] == "ci"
      assert length(vsm["levels"]) >= 2
      [mat_level, pipe_level | _] = vsm["levels"]
      assert Enum.any?(mat_level["nodes"], &(&1["name"] =~ "github.com"))
      [pipe_node] = pipe_level["nodes"]
      assert pipe_node["node_type"] == "PIPELINE"
      assert pipe_node["name"] == "ci"
    end

    test "includes trigger_info, fan_in, fan_out", %{pipeline: pipeline} do
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(pipeline.name, 4)
      [_, pipe_level | _] = vsm["levels"]
      [pipe_node] = pipe_level["nodes"]
      [inst] = pipe_node["instances"]
      assert inst["trigger_info"]["triggered_by"] == "4"
      assert is_integer(pipe_node["fan_in"])
      assert is_integer(pipe_node["fan_out"])
    end

    test "handles nil build_cause gracefully" do
      {:ok, p} =
        %ExGoCD.Pipelines.Pipeline{}
        |> ExGoCD.Pipelines.Pipeline.changeset(%{name: "nil-cause-pipe", group: "default", label_template: "${COUNT}"})
        |> ExGoCD.Repo.insert()

      {:ok, _} =
        %ExGoCD.Pipelines.PipelineInstance{}
        |> ExGoCD.Pipelines.PipelineInstance.changeset(%{
          pipeline_id: p.id, counter: 1, label: "1", natural_order: 1.0, build_cause: %{}
        })
        |> ExGoCD.Repo.insert()

      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm("nil-cause-pipe", 1)
      assert vsm["current_pipeline"] == "nil-cause-pipe"
    end

    test "computes duration with mixed DateTime/NaiveDateTime", %{pipeline: pipeline} do
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(pipeline.name, 4)
      [_, pipe_level | _] = vsm["levels"]
      [pipe_node] = pipe_level["nodes"]
      [inst] = pipe_node["instances"]
      stage = hd(inst["stages"])
      assert is_integer(stage["duration"])
    end
  end
end
