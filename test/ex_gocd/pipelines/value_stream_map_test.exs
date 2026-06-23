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

      assert [%{"id" => ^pipeline_name, "node_type" => "PIPELINE", "depth" => 1} = target_node] =
               target_level["nodes"]

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
        |> ExGoCD.Pipelines.Pipeline.changeset(%{
          name: "ci",
          group: "default",
          label_template: "${COUNT}"
        })
        |> ExGoCD.Repo.insert()

      {:ok, mat} =
        %ExGoCD.Pipelines.Material{}
        |> ExGoCD.Pipelines.Material.changeset(%{
          type: "git",
          url: "https://github.com/exgocd/ci.git",
          branch: "main"
        })
        |> ExGoCD.Repo.insert()

      ExGoCD.Repo.insert_all("pipelines_materials", [
        %{pipeline_id: pipeline.id, material_id: mat.id}
      ])

      pipeline =
        ExGoCD.Repo.get(ExGoCD.Pipelines.Pipeline, pipeline.id) |> ExGoCD.Repo.preload(:materials)

      {:ok, stage} =
        %ExGoCD.Pipelines.Stage{}
        |> ExGoCD.Pipelines.Stage.changeset(%{
          name: "build",
          pipeline_id: pipeline.id,
          order_id: 0
        })
        |> ExGoCD.Repo.insert()

      {:ok, instance} =
        %ExGoCD.Pipelines.PipelineInstance{}
        |> ExGoCD.Pipelines.PipelineInstance.changeset(%{
          pipeline_id: pipeline.id,
          counter: 4,
          label: "4",
          natural_order: 4.0,
          build_cause: %{"materialRevisions" => []}
        })
        |> ExGoCD.Repo.insert()

      completed_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      created_time =
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-300, :second)

      {:ok, _stage_instance} =
        %ExGoCD.Pipelines.StageInstance{}
        |> ExGoCD.Pipelines.StageInstance.changeset(%{
          stage_id: stage.id,
          pipeline_instance_id: instance.id,
          name: "build",
          counter: 1,
          order_id: 0,
          state: "Completed",
          result: "Passed",
          approval_type: "success",
          created_time: created_time,
          completed_at: completed_at
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
        |> ExGoCD.Pipelines.Pipeline.changeset(%{
          name: "nil-cause-pipe",
          group: "default",
          label_template: "${COUNT}"
        })
        |> ExGoCD.Repo.insert()

      {:ok, _} =
        %ExGoCD.Pipelines.PipelineInstance{}
        |> ExGoCD.Pipelines.PipelineInstance.changeset(%{
          pipeline_id: p.id,
          counter: 1,
          label: "1",
          natural_order: 1.0,
          build_cause: %{}
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
      {_p, _stage, _instance, _si} = create_pipeline_with_result("status-test", "Passed")
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm("status-test", 1)
      [_, pipe_level | _] = vsm["levels"]
      [pipe_node] = pipe_level["nodes"]
      [inst] = pipe_node["instances"]
      [vsm_stage] = inst["stages"]

      assert vsm_stage["status"] == "Passed",
             "VSM must use result (Passed), not lifecycle state (Completed). Got: #{inspect(vsm_stage["status"])}"
    end

    test "stage status uses result=Failed, not state=Completed" do
      {_p, _stage, _instance, _si} = create_pipeline_with_result("failed-test", "Failed")
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
      {:ok, upstream} =
        create_pipeline_with_material(
          "upstream-lib",
          "git",
          "https://github.com/d-led/upstream.git"
        )

      {:ok, comp_a} = create_pipeline_with_material("component-a", "dependency", "upstream-lib")
      {:ok, comp_b} = create_pipeline_with_material("component-b", "dependency", "upstream-lib")

      {:ok, integration} =
        create_pipeline_with_material("integration-pipeline", "dependency", "component-a")

      # integration-pipeline also depends on component-b (fan-in)
      {:ok, mat_b} = create_material("dependency", "component-b")

      ExGoCD.Repo.insert_all("pipelines_materials", [
        %{pipeline_id: integration.id, material_id: mat_b.id}
      ])

      # Create instance for upstream-lib (stage already created by helper)
      stage = ExGoCD.Repo.get_by!(ExGoCD.Pipelines.Stage, pipeline_id: upstream.id, name: "build")

      completed_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      created_time =
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-300, :second)

      {:ok, instance} =
        %ExGoCD.Pipelines.PipelineInstance{}
        |> ExGoCD.Pipelines.PipelineInstance.changeset(%{
          pipeline_id: upstream.id,
          counter: 5,
          label: "5",
          natural_order: 5.0,
          build_cause: %{"materialRevisions" => []}
        })
        |> ExGoCD.Repo.insert()

      {:ok, _si} =
        %ExGoCD.Pipelines.StageInstance{}
        |> ExGoCD.Pipelines.StageInstance.changeset(%{
          stage_id: stage.id,
          pipeline_instance_id: instance.id,
          name: "build",
          counter: 1,
          order_id: 0,
          state: "Building",
          result: "Unknown",
          approval_type: "success",
          created_time: created_time,
          completed_at: completed_at
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

    test "downstream nodes that never ran show GoCD-parity un-run instances", %{
      upstream: upstream
    } do
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(upstream.name, 5)
      [_mat, _pipe, downstream_level | _] = vsm["levels"]

      for node <- downstream_level["nodes"] do
        [inst] = node["instances"]
        stages = inst["stages"]

        refute Enum.empty?(stages), "downstream '#{node["name"]}' should have configured stages"

        # GoCD parity: un-run = EmptyPipelineIdentifier (counter=0, label="", locator="")
        assert inst["counter"] == 0,
               "un-run downstream '#{node["name"]}' should have counter=0, got #{inst["counter"]}"

        assert inst["label"] == ""
        assert inst["locator"] == ""

        # GoCD parity: NullStage → status=Unknown, no locator
        for stage <- stages do
          assert stage["status"] == "Unknown",
                 "un-run stage '#{stage["name"]}' in '#{node["name"]}' should be Unknown, got: #{stage["status"]}"

          assert stage["duration"] == 0
          assert stage["locator"] == ""
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

  # ── counter=0: GoCD EmptyPipelineIdentifier parity ───────────────────
  # In GoCD, counter=0 means "never run" / indeterminate.
  # hasCounter() returns counter > 0, locator is "" when counter==0,
  # stages are NullStage (status=Unknown).
  describe "counter=0 indeterminate VSM (GoCD EmptyPipelineIdentifier parity)" do
    setup do
      {:ok, pipeline} =
        %ExGoCD.Pipelines.Pipeline{}
        |> ExGoCD.Pipelines.Pipeline.changeset(%{
          name: "indeterminate-pipe",
          group: "default",
          label_template: "${COUNT}"
        })
        |> ExGoCD.Repo.insert()

      {:ok, mat} =
        %ExGoCD.Pipelines.Material{}
        |> ExGoCD.Pipelines.Material.changeset(%{
          type: "git",
          url: "https://github.com/exgocd/indeterminate.git",
          branch: "main"
        })
        |> ExGoCD.Repo.insert()

      ExGoCD.Repo.insert_all("pipelines_materials", [
        %{pipeline_id: pipeline.id, material_id: mat.id}
      ])

      # Configured stages (no instances — never run)
      {:ok, _build_stage} =
        %ExGoCD.Pipelines.Stage{}
        |> ExGoCD.Pipelines.Stage.changeset(%{
          name: "build",
          pipeline_id: pipeline.id,
          order_id: 0
        })
        |> ExGoCD.Repo.insert()

      {:ok, _test_stage} =
        %ExGoCD.Pipelines.Stage{}
        |> ExGoCD.Pipelines.Stage.changeset(%{
          name: "test",
          pipeline_id: pipeline.id,
          order_id: 1
        })
        |> ExGoCD.Repo.insert()

      %{pipeline: pipeline}
    end

    test "returns indeterminate VSM when requesting counter=0 for an existing pipeline", %{
      pipeline: pipeline
    } do
      # Given a pipeline that exists but has never run
      # When we request its value stream map with counter=0
      assert {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(pipeline.name, 0)

      # Then the current pipeline is set
      assert vsm["current_pipeline"] == "indeterminate-pipe"

      # And the pipeline node has the indeterminate instance
      [_, pipe_level | _] = vsm["levels"]
      [pipe_node] = pipe_level["nodes"]
      [inst] = pipe_node["instances"]

      # The instance is indeterminate: counter=0, empty label, no clickable locator
      assert inst["counter"] == 0
      assert inst["label"] == ""
      assert inst["locator"] == ""

      # All configured stages appear as Unknown (GoCD NullStage parity)
      stage_names = inst["stages"] |> Enum.map(& &1["name"])
      assert "build" in stage_names
      assert "test" in stage_names

      for stage <- inst["stages"] do
        assert stage["status"] == "Unknown",
               "stage '#{stage["name"]}' should be Unknown (un-run), got: #{stage["status"]}"

        assert stage["duration"] == 0
        assert stage["locator"] == ""
      end
    end

    test "counter=0 for a pipeline that does not exist returns :not_found" do
      # Given a pipeline name that doesn't exist
      # When requesting its VSM with counter=0
      # Then it returns :not_found — no indeterminate VSM for unknown pipelines
      assert {:error, :not_found} = ValueStreamMap.get_pipeline_vsm("nonexistent-pipeline", 0)
    end
  end

  describe "un-run downstream nodes (GoCD UnrunPipelineRevision parity)" do
    setup do
      # Given: upstream triggers downstream-a, but downstream-a has never run
      {:ok, upstream} =
        create_pipeline_with_material(
          "trigger-pipe",
          "git",
          "https://github.com/exgocd/trigger.git"
        )

      {:ok, downstream} = create_pipeline_with_material("never-ran", "dependency", "trigger-pipe")

      # downstream also has a second stage configured
      unless ExGoCD.Repo.get_by(ExGoCD.Pipelines.Stage,
               pipeline_id: downstream.id,
               name: "deploy"
             ) do
        %ExGoCD.Pipelines.Stage{}
        |> ExGoCD.Pipelines.Stage.changeset(%{
          name: "deploy",
          pipeline_id: downstream.id,
          order_id: 1
        })
        |> ExGoCD.Repo.insert()
      end

      # Create an instance for upstream so the VSM renders
      stage = ExGoCD.Repo.get_by!(ExGoCD.Pipelines.Stage, pipeline_id: upstream.id, name: "build")

      completed_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      created_time =
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-120, :second)

      {:ok, instance} =
        %ExGoCD.Pipelines.PipelineInstance{}
        |> ExGoCD.Pipelines.PipelineInstance.changeset(%{
          pipeline_id: upstream.id,
          counter: 1,
          label: "1",
          natural_order: 1.0,
          build_cause: %{"materialRevisions" => []}
        })
        |> ExGoCD.Repo.insert()

      {:ok, _si} =
        %ExGoCD.Pipelines.StageInstance{}
        |> ExGoCD.Pipelines.StageInstance.changeset(%{
          stage_id: stage.id,
          pipeline_instance_id: instance.id,
          name: "build",
          counter: 1,
          order_id: 0,
          state: "Completed",
          result: "Passed",
          approval_type: "success",
          created_time: created_time,
          completed_at: completed_at
        })
        |> ExGoCD.Repo.insert()

      %{upstream: upstream, downstream: downstream}
    end

    test "downstream that never ran shows as indeterminate (counter=0, Unknown stages)", %{
      upstream: upstream,
      downstream: downstream
    } do
      # When we view the VSM from the upstream pipeline
      {:ok, vsm} = ValueStreamMap.get_pipeline_vsm(upstream.name, 1)

      # Then the downstream level contains the never-run pipeline
      [_mat, _pipe, downstream_level | _] = vsm["levels"]
      downstream_node = Enum.find(downstream_level["nodes"], &(&1["name"] == downstream.name))
      assert downstream_node, "expected downstream '#{downstream.name}' in VSM levels"

      # And its instance is indeterminate — GoCD UnrunPipelineRevision parity
      [inst] = downstream_node["instances"]

      assert inst["counter"] == 0,
             "un-run pipeline should have counter=0 (EmptyPipelineIdentifier), got #{inst["counter"]}"

      assert inst["label"] == ""
      assert inst["locator"] == ""

      # And all configured stages show as Unknown (NullStage)
      refute Enum.empty?(inst["stages"]), "un-run pipeline should have configured stages"

      for stage <- inst["stages"] do
        assert stage["status"] == "Unknown",
               "un-run stage '#{stage["name"]}' should be Unknown, got: #{stage["status"]}"

        assert stage["duration"] == 0
        assert stage["locator"] == ""
      end
    end
  end

  defp create_pipeline_with_material(name, mat_type, mat_url) do
    {:ok, pipeline} =
      %ExGoCD.Pipelines.Pipeline{}
      |> ExGoCD.Pipelines.Pipeline.changeset(%{
        name: name,
        group: "default",
        label_template: "${COUNT}"
      })
      |> ExGoCD.Repo.insert()

    {:ok, material} = create_material(mat_type, mat_url)

    ExGoCD.Repo.insert_all("pipelines_materials", [
      %{pipeline_id: pipeline.id, material_id: material.id}
    ])

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
