defmodule ExGoCD.Pipelines.JobInstanceTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.{
    Pipeline,
    Stage,
    Job,
    PipelineInstance,
    StageInstance,
    JobInstance
  }

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

    pipeline_instance =
      PipelineInstance.changeset(%PipelineInstance{}, %{
        counter: 1,
        label: "1",
        natural_order: 1.0,
        build_cause: %{"approver" => "user"},
        pipeline_id: pipeline.id
      })
      |> Repo.insert!()

    stage_instance =
      StageInstance.changeset(%StageInstance{}, %{
        name: "build",
        counter: 1,
        order_id: 1,
        state: "Building",
        result: "Unknown",
        approval_type: "success",
        created_time: DateTime.utc_now(),
        pipeline_instance_id: pipeline_instance.id
      })
      |> Repo.insert!()

    %{job: job, stage_instance: stage_instance}
  end

  describe "changeset/2" do
    test "valid changeset with required fields", %{stage_instance: stage_instance} do
      changeset =
        JobInstance.changeset(%JobInstance{}, %{
          name: "compile",
          scheduled_at: ~N[2024-01-01 10:00:00],
          stage_instance_id: stage_instance.id
        })

      assert changeset.valid?
    end

    test "requires name, scheduled_at, stage_instance_id" do
      changeset = JobInstance.changeset(%JobInstance{}, %{})
      errors = errors_on(changeset)

      assert %{
               name: ["can't be blank"],
               scheduled_at: ["can't be blank"],
               stage_instance_id: ["can't be blank"]
             } = errors
    end

    test "validates state inclusion" do
      changeset =
        JobInstance.changeset(%JobInstance{}, %{
          name: "compile",
          state: "invalid",
          result: "Unknown",
          job_id: 1,
          stage_instance_id: 1
        })

      assert %{state: ["is invalid"]} = errors_on(changeset)
    end

    test "valid state values", %{job: job, stage_instance: stage_instance} do
      for state <- ["Scheduled", "Assigned", "Preparing", "Building", "Completing", "Completed"] do
        changeset =
          JobInstance.changeset(%JobInstance{}, %{
            name: "compile",
            state: state,
            result: "Unknown",
            job_id: job.id,
            stage_instance_id: stage_instance.id
          })

        refute Map.has_key?(errors_on(changeset), :state),
               "#{state} should be valid"
      end
    end

    test "validates result inclusion" do
      changeset =
        JobInstance.changeset(%JobInstance{}, %{
          name: "compile",
          state: "Scheduled",
          result: "invalid",
          job_id: 1,
          stage_instance_id: 1
        })

      assert %{result: ["is invalid"]} = errors_on(changeset)
    end

    test "valid result values", %{job: job, stage_instance: stage_instance} do
      for result <- ["Passed", "Failed", "Cancelled", "Unknown"] do
        changeset =
          JobInstance.changeset(%JobInstance{}, %{
            name: "compile",
            state: "Scheduled",
            result: result,
            job_id: job.id,
            stage_instance_id: stage_instance.id
          })

        refute Map.has_key?(errors_on(changeset), :result),
               "#{result} should be valid"
      end
    end

    test "sets default state" do
      changeset =
        JobInstance.changeset(%JobInstance{}, %{
          name: "compile",
          result: "Unknown",
          job_id: 1,
          stage_instance_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :state) == "Scheduled"
    end

    test "sets default result" do
      changeset =
        JobInstance.changeset(%JobInstance{}, %{
          name: "compile",
          state: "Scheduled",
          job_id: 1,
          stage_instance_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :result) == "Unknown"
    end
  end
end
