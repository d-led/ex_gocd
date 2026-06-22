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

    test "stage status uses result (Passed/Failed), not lifecycle state (Completed)" do
      {:ok, p} =
        %ExGoCD.Pipelines.Pipeline{}
        |> ExGoCD.Pipelines.Pipeline.changeset(%{name: "status-test", group: "default", label_template: "${COUNT}"})
        |> ExGoCD.Repo.insert()

      {:ok, stage} =
        %ExGoCD.Pipelines.Stage{}
        |> ExGoCD.Pipelines.Stage.changeset(%{name: "build", pipeline_id: p.id, order_id: 0})
        |> ExGoCD.Repo.insert()

      completed_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      created_time = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-300, :second)

      {:ok, instance} =
        %ExGoCD.Pipelines.PipelineInstance{}
        |> ExGoCD.Pipelines.PipelineInstance.changeset(%{
          pipeline_id: p.id, counter: 1, label: "1", natural_order: 1.0,
          build_cause: %{"materialRevisions" => []}
        })
        |> ExGoCD.Repo.insert()

      # Stage is Completed with result Passed — VSM must show "Passed", NOT "Completed"
      {:ok, _} =
        %ExGoCD.Pipelines.StageInstance{}
        |> ExGoCD.Pipelines.StageInstance.changeset(%{
          stage_id: stage.id, pipeline_instance_id: instance.id,
          name: "build", counter: 1, order_id: 0,
          state: "Completed", result: "Passed",
          approval_type: "success", created_time: created_time, completed_at: completed_at
        })
        |> ExGoCD.Repo.insert()

      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm("status-test", 1)
      [_, pipe_level | _] = vsm["levels"]
      [pipe_node] = pipe_level["nodes"]
      [inst] = pipe_node["instances"]
      [vsm_stage] = inst["stages"]

      # THIS is the critical assertion: result over state
      assert vsm_stage["status"] == "Passed",
        "VSM must use result (Passed), not lifecycle state (Completed). Got: #{inspect(vsm_stage["status"])}"
    end

    test "stage status uses result=Failed, not state=Completed" do
      {:ok, p} =
        %ExGoCD.Pipelines.Pipeline{}
        |> ExGoCD.Pipelines.Pipeline.changeset(%{name: "failed-test", group: "default", label_template: "${COUNT}"})
        |> ExGoCD.Repo.insert()

      {:ok, stage} =
        %ExGoCD.Pipelines.Stage{}
        |> ExGoCD.Pipelines.Stage.changeset(%{name: "build", pipeline_id: p.id, order_id: 0})
        |> ExGoCD.Repo.insert()

      completed_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      created_time = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-300, :second)

      {:ok, instance} =
        %ExGoCD.Pipelines.PipelineInstance{}
        |> ExGoCD.Pipelines.PipelineInstance.changeset(%{
          pipeline_id: p.id, counter: 1, label: "1", natural_order: 1.0,
          build_cause: %{"materialRevisions" => []}
        })
        |> ExGoCD.Repo.insert()

      {:ok, _} =
        %ExGoCD.Pipelines.StageInstance{}
        |> ExGoCD.Pipelines.StageInstance.changeset(%{
          stage_id: stage.id, pipeline_instance_id: instance.id,
          name: "build", counter: 1, order_id: 0,
          state: "Completed", result: "Failed",
          approval_type: "success", created_time: created_time, completed_at: completed_at
        })
        |> ExGoCD.Repo.insert()

      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm("failed-test", 1)
      [_, pipe_level | _] = vsm["levels"]
      [pipe_node] = pipe_level["nodes"]
      [inst] = pipe_node["instances"]
      [vsm_stage] = inst["stages"]

      assert vsm_stage["status"] == "Failed",
        "VSM must use result (Failed), not lifecycle state. Got: #{inspect(vsm_stage["status"])}"
    end
  end

  describe "diamond fan-in/fan-out VSM" do
    setup do
      # Create the diamond: upstream-lib → (component-a, component-b) → integration-pipeline
      {:ok, upstream} = create_pipeline_with_material("upstream-lib", "git", "https://github.com/d-led/upstream.git")

      {:ok, comp_a} = create_pipeline_with_material("component-a", "dependency", "upstream-lib")
      {:ok, comp_b} = create_pipeline_with_material("component-b", "dependency", "upstream-lib")
      {:ok, integration} = create_pipeline_with_material("integration-pipeline", "dependency", "component-a")
      # integration-pipeline also depends on component-b (fan-in)
      {:ok, mat_b} = create_material("dependency", "component-b")
      ExGoCD.Repo.insert_all("pipelines_materials", [%{pipeline_id: integration.id, material_id: mat_b.id}])

      # Create instance for upstream-lib (stage already created by helper)
      stage = ExGoCD.Repo.get_by!(ExGoCD.Pipelines.Stage, pipeline_id: upstream.id, name: "build")

      completed_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      created_time = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-300, :second)

      {:ok, instance} =
        %ExGoCD.Pipelines.PipelineInstance{}
        |> ExGoCD.Pipelines.PipelineInstance.changeset(%{
          pipeline_id: upstream.id, counter: 5, label: "5", natural_order: 5.0,
          build_cause: %{"materialRevisions" => []}
        })
        |> ExGoCD.Repo.insert()

      {:ok, _si} =
        %ExGoCD.Pipelines.StageInstance{}
        |> ExGoCD.Pipelines.StageInstance.changeset(%{
          stage_id: stage.id, pipeline_instance_id: instance.id,
          name: "build", counter: 1, order_id: 0, state: "Building", result: "Unknown",
          approval_type: "success", created_time: created_time, completed_at: completed_at
        })
        |> ExGoCD.Repo.insert()

      %{
        upstream: upstream,
        comp_a: comp_a,
        comp_b: comp_b,
        integration: integration,
        instance: instance
      }
    end

    test "shows 4 levels for the diamond", %{upstream: upstream} do
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(upstream.name, 5)
      assert length(vsm["levels"]) == 4
    end

    test "level 2 shows downstream pipelines component-a and component-b", %{upstream: upstream} do
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(upstream.name, 5)
      [_mat, _pipe, downstream_level | _] = vsm["levels"]
      names = downstream_level["nodes"] |> Enum.map(& &1["name"])
      assert "component-a" in names
      assert "component-b" in names
    end

    test "level 3 shows fan-in integration-pipeline", %{upstream: upstream} do
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(upstream.name, 5)
      levels = vsm["levels"]
      assert length(levels) >= 4
      last_level = Enum.at(levels, 3)
      names = last_level["nodes"] |> Enum.map(& &1["name"])
      assert "integration-pipeline" in names
    end

    test "downstream nodes have stage indicators (mock or un-run)", %{upstream: upstream} do
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(upstream.name, 5)
      [_mat, _pipe, downstream_level | _] = vsm["levels"]

      for node <- downstream_level["nodes"] do
        [inst] = node["instances"]
        stages = inst["stages"]

        # Downstreams should have at least one stage configured
        refute Enum.empty?(stages), "downstream #{node["name"]} should have configured stages"
        # Each stage must have a name and status
        for stage <- stages do
          assert is_binary(stage["name"]), "stage must have a name"
          assert is_binary(stage["status"]), "stage must have a status: #{inspect(stage)}"
        end
      end
    end

    test "upstream node shows fan-out count", %{upstream: upstream} do
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(upstream.name, 5)
      [_, pipe_level | _] = vsm["levels"]
      [pipe_node] = pipe_level["nodes"]
      assert pipe_node["fan_out"] >= 2
      assert pipe_node["name"] == "upstream-lib"
    end

    test "integration-pipeline has two parents (fan-in)", %{upstream: upstream} do
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(upstream.name, 5)
      levels = vsm["levels"]
      last_level = Enum.at(levels, 3)
      [integration_node] = last_level["nodes"]
      parents = integration_node["parents"]
      assert "component-a" in parents
      assert "component-b" in parents
    end
  end

  defp create_pipeline_with_material(name, mat_type, mat_url) do
    {:ok, pipeline} =
      %ExGoCD.Pipelines.Pipeline{}
      |> ExGoCD.Pipelines.Pipeline.changeset(%{name: name, group: "default", label_template: "${COUNT}"})
      |> ExGoCD.Repo.insert()

    {:ok, material} = create_material(mat_type, mat_url)
    ExGoCD.Repo.insert_all("pipelines_materials", [%{pipeline_id: pipeline.id, material_id: material.id}])

    # Ensure each pipeline has a stage config (needed for un-run stage population)
    unless ExGoCD.Repo.get_by(ExGoCD.Pipelines.Stage, pipeline_id: pipeline.id, name: "build") do
      %ExGoCD.Pipelines.Stage{}
      |> ExGoCD.Pipelines.Stage.changeset(%{name: "build", pipeline_id: pipeline.id, order_id: 0})
      |> ExGoCD.Repo.insert()
    end

    {:ok, pipeline}
  end

  defp create_material(type, url) do
    %ExGoCD.Pipelines.Material{}
    |> ExGoCD.Pipelines.Material.changeset(%{type: type, url: url, branch: "main"})
    |> ExGoCD.Repo.insert()
  end
end
