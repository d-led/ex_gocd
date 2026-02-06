defmodule ExGoCD.Pipelines.StageTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Pipeline, Stage}

  setup do
    pipeline =
      Pipeline.changeset(%Pipeline{}, %{name: "test-pipeline"})
      |> Repo.insert!()

    %{pipeline: pipeline}
  end

  describe "changeset/2" do
    test "valid changeset with required fields", %{pipeline: pipeline} do
      changeset =
        Stage.changeset(%Stage{}, %{
          name: "build",
          approval_type: "success",
          pipeline_id: pipeline.id
        })

      assert changeset.valid?
    end

    test "requires name and pipeline_id" do
      changeset = Stage.changeset(%Stage{}, %{})
      errors = errors_on(changeset)
      assert %{name: ["can't be blank"], pipeline_id: ["can't be blank"]} = errors
    end

    test "validates approval_type inclusion" do
      changeset =
        Stage.changeset(%Stage{}, %{
          name: "test",
          pipeline_id: 1,
          approval_type: "invalid"
        })

      assert %{approval_type: ["is invalid"]} = errors_on(changeset)
    end

    test "valid approval_type values", %{pipeline: pipeline} do
      for approval_type <- ["success", "manual"] do
        changeset =
          Stage.changeset(%Stage{}, %{
            name: "test",
            pipeline_id: pipeline.id,
            approval_type: approval_type
          })

        refute Map.has_key?(errors_on(changeset), :approval_type),
               "#{approval_type} should be valid"
      end
    end

    test "sets default approval_type" do
      changeset = Stage.changeset(%Stage{}, %{name: "test", pipeline_id: 1})
      assert Ecto.Changeset.get_field(changeset, :approval_type) == "success"
    end
  end

  describe "database constraints" do
    test "enforces unique name per pipeline", %{pipeline: pipeline} do
      Stage.changeset(%Stage{}, %{
        name: "build",
        pipeline_id: pipeline.id
      })
      |> Repo.insert!()

      changeset = Stage.changeset(%Stage{}, %{
        name: "build",
        pipeline_id: pipeline.id
      })
      assert {:error, changeset} = Repo.insert(changeset)
      assert %{name: [_]} = errors_on(changeset)
    end

    test "allows same stage name in different pipelines", %{pipeline: pipeline} do
      other_pipeline =
        Pipeline.changeset(%Pipeline{}, %{name: "other-pipeline"})
        |> Repo.insert!()

      Stage.changeset(%Stage{}, %{name: "build", pipeline_id: pipeline.id})
      |> Repo.insert!()

      stage2 =
        Stage.changeset(%Stage{}, %{name: "build", pipeline_id: other_pipeline.id})
        |> Repo.insert!()

      assert stage2.name == "build"
    end
  end
end
