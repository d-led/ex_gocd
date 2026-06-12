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
end
