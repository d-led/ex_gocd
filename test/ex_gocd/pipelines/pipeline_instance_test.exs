defmodule ExGoCD.Pipelines.PipelineInstanceTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance}

  setup do
    pipeline =
      Pipeline.changeset(%Pipeline{}, %{name: "test-pipeline"})
      |> Repo.insert!()

    %{pipeline: pipeline}
  end

  describe "changeset/2" do
    test "valid changeset with required fields", %{pipeline: pipeline} do
      changeset =
        PipelineInstance.changeset(%PipelineInstance{}, %{
          counter: 1,
          label: "1",
          status: "Building",
          triggered_by: "user@example.com",
          pipeline_id: pipeline.id
        })

      assert changeset.valid?
    end

    test "requires counter, label, triggered_by, and pipeline_id" do
      changeset = PipelineInstance.changeset(%PipelineInstance{}, %{})
      errors = errors_on(changeset)

      assert %{
               counter: ["can't be blank"],
               label: ["can't be blank"],
               triggered_by: ["can't be blank"],
               pipeline_id: ["can't be blank"]
             } = errors
    end

    test "validates counter is positive" do
      changeset =
        PipelineInstance.changeset(%PipelineInstance{}, %{
          counter: 0,
          label: "0",
          status: "Building",
          triggered_by: "user",
          pipeline_id: 1
        })

      assert %{counter: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "validates status inclusion" do
      changeset =
        PipelineInstance.changeset(%PipelineInstance{}, %{
          counter: 1,
          label: "1",
          status: "invalid",
          triggered_by: "user",
          pipeline_id: 1
        })

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "valid status values", %{pipeline: pipeline} do
      for status <- ["Building", "Passed", "Failed", "Cancelled", "Paused"] do
        changeset =
          PipelineInstance.changeset(%PipelineInstance{}, %{
            counter: 1,
            label: "1",
            status: status,
            triggered_by: "user",
            pipeline_id: pipeline.id
          })

        refute Map.has_key?(errors_on(changeset), :status),
               "#{status} should be valid"
      end
    end

    test "sets default status" do
      changeset =
        PipelineInstance.changeset(%PipelineInstance{}, %{
          counter: 1,
          label: "1",
          triggered_by: "user",
          pipeline_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :status) == "Building"
    end
  end

  describe "database constraints" do
    test "enforces unique counter per pipeline", %{pipeline: pipeline} do
      PipelineInstance.changeset(%PipelineInstance{}, %{
        counter: 1,
        label: "1",
        status: "Building",
        triggered_by: "user",
        pipeline_id: pipeline.id
      })
      |> Repo.insert!()

      changeset = PipelineInstance.changeset(%PipelineInstance{}, %{
        counter: 1,
        label: "1-duplicate",
        status: "Building",
        triggered_by: "user",
        pipeline_id: pipeline.id
      })
      assert {:error, changeset} = Repo.insert(changeset)
      assert %{pipeline_id: [_]} = errors_on(changeset)
    end

    test "allows same counter in different pipelines", %{pipeline: pipeline} do
      other_pipeline =
        Pipeline.changeset(%Pipeline{}, %{name: "other-pipeline"})
        |> Repo.insert!()

      PipelineInstance.changeset(%PipelineInstance{}, %{
        counter: 1,
        label: "1",
        status: "Building",
        triggered_by: "user",
        pipeline_id: pipeline.id
      })
      |> Repo.insert!()

      instance2 =
        PipelineInstance.changeset(%PipelineInstance{}, %{
          counter: 1,
          label: "1",
          status: "Building",
          triggered_by: "user",
          pipeline_id: other_pipeline.id
        })
        |> Repo.insert!()

      assert instance2.counter == 1
    end
  end
end
