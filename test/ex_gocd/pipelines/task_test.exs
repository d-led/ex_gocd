defmodule ExGoCD.Pipelines.TaskTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{Pipeline, Stage, Job, Task}

  setup do
    pipeline =
      Pipeline.changeset(%Pipeline{}, %{name: "test-pipeline"})
      |> Repo.insert!()

    stage =
      Stage.changeset(%Stage{}, %{name: "build", pipeline_id: pipeline.id})
      |> Repo.insert!()

    job =
      Job.changeset(%Job{}, %{name: "compile", stage_id: stage.id})
      |> Repo.insert!()

    %{job: job}
  end

  describe "changeset/2" do
    test "valid exec task", %{job: job} do
      changeset =
        Task.changeset(%Task{}, %{
          type: "exec",
          command: "make",
          arguments: ["build", "test"],
          run_if: "passed",
          job_id: job.id
        })

      assert changeset.valid?
    end

    test "requires type and job_id" do
      changeset = Task.changeset(%Task{}, %{})
      errors = errors_on(changeset)
      assert %{type: ["can't be blank"], job_id: ["can't be blank"]} = errors
    end

    test "validates type inclusion" do
      changeset =
        Task.changeset(%Task{}, %{
          type: "invalid",
          job_id: 1
        })

      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "valid task types", %{job: job} do
      for type <- ["exec", "ant", "nant", "rake", "fetch", "plugin"] do
        changeset =
          Task.changeset(%Task{}, %{
            type: type,
            job_id: job.id
          })

        refute Map.has_key?(errors_on(changeset), :type),
               "#{type} should be valid"
      end
    end

    test "validates run_if inclusion" do
      changeset =
        Task.changeset(%Task{}, %{
          type: "exec",
          job_id: 1,
          run_if: "invalid"
        })

      assert %{run_if: ["is invalid"]} = errors_on(changeset)
    end

    test "valid run_if values", %{job: job} do
      for run_if <- ["passed", "failed", "any"] do
        changeset =
          Task.changeset(%Task{}, %{
            type: "exec",
            job_id: job.id,
            run_if: run_if
          })

        refute Map.has_key?(errors_on(changeset), :run_if),
               "#{run_if} should be valid"
      end
    end

    test "sets default run_if" do
      changeset = Task.changeset(%Task{}, %{type: "exec", job_id: 1})
      assert Ecto.Changeset.get_field(changeset, :run_if) == "passed"
    end
  end
end
