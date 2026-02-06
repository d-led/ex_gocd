defmodule ExGoCD.Pipelines.JobTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Pipeline, Stage, Job}

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

    %{stage: stage}
  end

  describe "changeset/2" do
    test "valid changeset with required fields", %{stage: stage} do
      changeset =
        Job.changeset(%Job{}, %{
          name: "compile",
          stage_id: stage.id
        })

      assert changeset.valid?
    end

    test "requires name and stage_id" do
      changeset = Job.changeset(%Job{}, %{})
      errors = errors_on(changeset)
      assert %{name: ["can't be blank"], stage_id: ["can't be blank"]} = errors
    end

    test "accepts resources as array", %{stage: stage} do
      changeset =
        Job.changeset(%Job{}, %{
          name: "test",
          stage_id: stage.id,
          resources: ["java", "linux"]
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :resources) == ["java", "linux"]
    end

    test "accepts environment_variables as map", %{stage: stage} do
      changeset =
        Job.changeset(%Job{}, %{
          name: "test",
          stage_id: stage.id,
          environment_variables: %{"JAVA_HOME" => "/usr/lib/jvm/java-11"}
        })

      assert changeset.valid?
    end

    test "sets default empty arrays and maps" do
      changeset = Job.changeset(%Job{}, %{name: "test", stage_id: 1})
      assert Ecto.Changeset.get_field(changeset, :resources) == []
      assert Ecto.Changeset.get_field(changeset, :environment_variables) == %{}
    end
  end

  describe "database constraints" do
    test "enforces unique name per stage", %{stage: stage} do
      Job.changeset(%Job{}, %{name: "compile", stage_id: stage.id})
      |> Repo.insert!()

      changeset = Job.changeset(%Job{}, %{name: "compile", stage_id: stage.id})
      assert {:error, changeset} = Repo.insert(changeset)
      assert %{name: [_]} = errors_on(changeset)
    end
  end
end
