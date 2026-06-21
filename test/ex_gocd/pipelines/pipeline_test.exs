defmodule ExGoCD.Pipelines.PipelineTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.Pipeline

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset =
        Pipeline.changeset(%Pipeline{}, %{
          name: "build-pipeline",
          group: "build-group",
          label_template: "${COUNT}",
          lock_behavior: "none"
        })

      assert changeset.valid?
    end

    test "requires name" do
      changeset = Pipeline.changeset(%Pipeline{}, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates lock_behavior inclusion" do
      changeset =
        Pipeline.changeset(%Pipeline{}, %{
          name: "test",
          lock_behavior: "invalid"
        })

      assert %{lock_behavior: ["is invalid"]} = errors_on(changeset)
    end

    test "valid lock_behavior values" do
      for lock_behavior <- ["none", "unlockWhenFinished", "lockOnFailure"] do
        changeset =
          Pipeline.changeset(%Pipeline{}, %{
            name: "test",
            lock_behavior: lock_behavior
          })

        refute Map.has_key?(errors_on(changeset), :lock_behavior),
               "#{lock_behavior} should be valid"
      end
    end

    test "sets default label_template" do
      changeset = Pipeline.changeset(%Pipeline{}, %{name: "test"})
      assert Ecto.Changeset.get_field(changeset, :label_template) == "${COUNT}"
    end

    test "sets default lock_behavior" do
      changeset = Pipeline.changeset(%Pipeline{}, %{name: "test"})
      assert Ecto.Changeset.get_field(changeset, :lock_behavior) == "none"
    end
  end

  describe "database constraints" do
    test "enforces unique name" do
      Pipeline.changeset(%Pipeline{}, %{name: "unique-pipeline"})
      |> Repo.insert!()

      changeset = Pipeline.changeset(%Pipeline{}, %{name: "unique-pipeline"})
      assert {:error, changeset} = Repo.insert(changeset)
      assert %{name: [_]} = errors_on(changeset)
    end
  end
end
