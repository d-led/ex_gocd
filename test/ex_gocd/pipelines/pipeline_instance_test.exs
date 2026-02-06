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
          natural_order: 1.0,
          build_cause: %{
            "approver" => "user@example.com",
            "material_revisions" => []
          },
          pipeline_id: pipeline.id
        })

      assert changeset.valid?
    end

    test "requires counter, label, natural_order, build_cause, and pipeline_id" do
      changeset = PipelineInstance.changeset(%PipelineInstance{}, %{})
      errors = errors_on(changeset)

      assert %{
               counter: ["can't be blank"],
               label: ["can't be blank"],
               natural_order: ["can't be blank"],
               build_cause: ["can't be blank"],
               pipeline_id: ["can't be blank"]
             } = errors
    end

    test "validates counter is positive" do
      changeset =
        PipelineInstance.changeset(%PipelineInstance{}, %{
          counter: 0,
          label: "0",
          natural_order: 0.0,
          build_cause: %{"approver" => "user"},
          pipeline_id: 1
        })

      assert %{counter: ["must be greater than 0"]} = errors_on(changeset)
    end
  end

  describe "database constraints" do
    test "enforces unique counter per pipeline", %{pipeline: pipeline} do
      PipelineInstance.changeset(%PipelineInstance{}, %{
        counter: 1,
        label: "1",
        natural_order: 1.0,
        build_cause: %{"approver" => "user"},
        pipeline_id: pipeline.id
      })
      |> Repo.insert!()

      changeset =
        PipelineInstance.changeset(%PipelineInstance{}, %{
          counter: 1,
          label: "1-duplicate",
          natural_order: 2.0,
          build_cause: %{"approver" => "user"},
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
        natural_order: 1.0,
        build_cause: %{"approver" => "user"},
        pipeline_id: pipeline.id
      })
      |> Repo.insert!()

      instance2 =
        PipelineInstance.changeset(%PipelineInstance{}, %{
          counter: 1,
          label: "1",
          natural_order: 1.0,
          build_cause: %{"approver" => "user"},
          pipeline_id: other_pipeline.id
        })
        |> Repo.insert!()

      assert instance2.counter == 1
    end
  end
end
