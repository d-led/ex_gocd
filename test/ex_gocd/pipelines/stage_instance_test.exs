defmodule ExGoCD.Pipelines.StageInstanceTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Pipeline, Stage, PipelineInstance, StageInstance}

  setup do
    pipeline =
      Pipeline.changeset(%Pipeline{}, %{name: "test-pipeline"})
      |> Repo.insert!()

    stage =
      Stage.changeset(%Stage{}, %{
        name: "build",
        pipeline_id: pipeline.id
      })
      |> Repo.insert!()

    pipeline_instance =
      PipelineInstance.changeset(%PipelineInstance{}, %{
        counter: 1,
        label: "1",
        status: "Building",
        triggered_by: "user",
        pipeline_id: pipeline.id
      })
      |> Repo.insert!()

    %{stage: stage, pipeline_instance: pipeline_instance}
  end

  describe "changeset/2" do
    test "valid changeset with required fields", %{
      stage: stage,
      pipeline_instance: pipeline_instance
    } do
      changeset =
        StageInstance.changeset(%StageInstance{}, %{
          name: "build",
          counter: 1,
          approval_type: "success",
          result: "Unknown",
          state: "Building",
          stage_id: stage.id,
          pipeline_instance_id: pipeline_instance.id
        })

      assert changeset.valid?
    end

    test "requires name, counter, approval_type, stage_id, pipeline_instance_id" do
      changeset = StageInstance.changeset(%StageInstance{}, %{})
      errors = errors_on(changeset)

      assert %{
               name: ["can't be blank"],
               counter: ["can't be blank"],
               approval_type: ["can't be blank"],
               stage_id: ["can't be blank"],
               pipeline_instance_id: ["can't be blank"]
             } = errors
    end

    test "validates counter is positive" do
      changeset =
        StageInstance.changeset(%StageInstance{}, %{
          name: "build",
          counter: 0,
          approval_type: "success",
          result: "Unknown",
          state: "Building",
          stage_id: 1,
          pipeline_instance_id: 1
        })

      assert %{counter: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "validates result inclusion" do
      changeset =
        StageInstance.changeset(%StageInstance{}, %{
          name: "build",
          counter: 1,
          approval_type: "success",
          result: "invalid",
          state: "Building",
          stage_id: 1,
          pipeline_instance_id: 1
        })

      assert %{result: ["is invalid"]} = errors_on(changeset)
    end

    test "valid result values", %{stage: stage, pipeline_instance: pipeline_instance} do
      for result <- ["Passed", "Failed", "Cancelled", "Unknown"] do
        changeset =
          StageInstance.changeset(%StageInstance{}, %{
            name: "build",
            counter: 1,
            approval_type: "success",
            result: result,
            state: "Building",
            stage_id: stage.id,
            pipeline_instance_id: pipeline_instance.id
          })

        refute Map.has_key?(errors_on(changeset), :result),
               "#{result} should be valid"
      end
    end

    test "validates state inclusion" do
      changeset =
        StageInstance.changeset(%StageInstance{}, %{
          name: "build",
          counter: 1,
          approval_type: "success",
          result: "Unknown",
          state: "invalid",
          stage_id: 1,
          pipeline_instance_id: 1
        })

      assert %{state: ["is invalid"]} = errors_on(changeset)
    end

    test "valid state values", %{stage: stage, pipeline_instance: pipeline_instance} do
      for state <- ["Building", "Completed", "Cancelled"] do
        changeset =
          StageInstance.changeset(%StageInstance{}, %{
            name: "build",
            counter: 1,
            approval_type: "success",
            result: "Unknown",
            state: state,
            stage_id: stage.id,
            pipeline_instance_id: pipeline_instance.id
          })

        refute Map.has_key?(errors_on(changeset), :state),
               "#{state} should be valid"
      end
    end
  end

  describe "database constraints" do
    test "enforces unique name/counter per pipeline instance", %{
      stage: stage,
      pipeline_instance: pipeline_instance
    } do
      StageInstance.changeset(%StageInstance{}, %{
        name: "build",
        counter: 1,
        approval_type: "success",
        result: "Unknown",
        state: "Building",
        stage_id: stage.id,
        pipeline_instance_id: pipeline_instance.id
      })
      |> Repo.insert!()

      changeset = StageInstance.changeset(%StageInstance{}, %{
        name: "build",
        counter: 1,
        approval_type: "success",
        result: "Unknown",
        state: "Building",
        stage_id: stage.id,
        pipeline_instance_id: pipeline_instance.id
      })
      assert {:error, changeset} = Repo.insert(changeset)
      assert %{pipeline_instance_id: [_]} = errors_on(changeset)
    end
  end
end
