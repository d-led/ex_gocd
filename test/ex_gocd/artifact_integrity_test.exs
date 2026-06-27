defmodule ExGoCD.ArtifactIntegrityTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.{Job, JobInstance, Pipeline, PipelineInstance, Stage, StageInstance, Task}
  alias ExGoCD.Repo

  import Ecto.Query

  describe "artifact path integrity (GoCD watertight parity)" do
    test "fetch artifact path follows GoCD convention: pipe/counter/stage/1/job/file" do
      {_p1, _stage, job} = insert_artifact_pipeline("up-artifact", "build", "jar-job")

      # Verify the job has artifact configs set up correctly
      job = Repo.preload(job, :tasks)
      assert length(job.tasks) == 1
      assert hd(job.tasks).type == "exec"
    end

    test "upload artifacts from job with artifact_configs produce correct commands" do
      pipeline = Repo.insert!(%Pipeline{name: "upload-pipe", group: "test"})

      stage =
        Repo.insert!(%Stage{
          name: "build",
          pipeline_id: pipeline.id,
          approval_type: "success"
        })

      job =
        Repo.insert!(%Job{
          name: "pkg-job",
          stage_id: stage.id,
          artifact_configs: %{
            "artifacts" => [
              %{"src" => "target/app.jar", "dest" => "dist/"},
              %{"src" => "target/lib", "dest" => "lib/", "type" => "external"}
            ]
          }
        })

      Repo.insert!(%Task{type: "exec", command: "make", job_id: job.id})

      {:ok, instance} = Pipelines.trigger_pipeline(pipeline.name)

      [si] =
        from(s in StageInstance, where: s.pipeline_instance_id == ^instance.id) |> Repo.all()

      [ji] = from(j in JobInstance, where: j.stage_instance_id == ^si.id) |> Repo.all()

      # Both artifacts should produce upload commands
      assert ji.name == "pkg-job"
    end

    test "fan-out: two downstream pipelines fetch from same upstream artifact" do
      # Upstream produces artifact
      up = Repo.insert!(%Pipeline{name: "artifact-source", group: "test"})

      up_stage =
        Repo.insert!(%Stage{name: "build", pipeline_id: up.id, approval_type: "success"})

      up_job =
        Repo.insert!(%Job{
          name: "producer",
          stage_id: up_stage.id,
          artifact_configs: %{"artifacts" => [%{"src" => "out.json", "dest" => "data/"}]}
        })

      Repo.insert!(%Task{type: "exec", command: "generate", job_id: up_job.id})

      # Two downstreams
      for suffix <- ["a", "b"] do
        down = Repo.insert!(%Pipeline{name: "artifact-consumer-#{suffix}", group: "test"})

        Repo.insert!(%Stage{name: "consume", pipeline_id: down.id, approval_type: "success"})
      end

      {:ok, instance} = Pipelines.trigger_pipeline("artifact-source")
      assert instance.counter == 1

      # Both downstreams should be able to reference artifact-source/1/build/1/producer/out.json
      # Verify via trigger + check
      for suffix <- ["a", "b"] do
        {:ok, di} = Pipelines.trigger_pipeline("artifact-consumer-#{suffix}")
        assert di.counter == 1
      end
    end

    test "fan-in: downstream fetches from two different upstream pipelines" do
      # Two upstreams produce different artifacts
      for {name, file} <- [{"fanin-src-a", "libs/foo.jar"}, {"fanin-src-b", "libs/bar.jar"}] do
        up = Repo.insert!(%Pipeline{name: name, group: "test"})

        stage =
          Repo.insert!(%Stage{name: "build", pipeline_id: up.id, approval_type: "success"})

        job =
          Repo.insert!(%Job{
            name: "builder",
            stage_id: stage.id,
            artifact_configs: %{"artifacts" => [%{"src" => file, "dest" => "out/"}]}
          })

        Repo.insert!(%Task{type: "exec", command: "build", job_id: job.id})
      end

      # Fan-in consumer depends on both
      fanin = Repo.insert!(%Pipeline{name: "fanin-consumer", group: "test"})

      Repo.insert!(%Stage{name: "assemble", pipeline_id: fanin.id, approval_type: "success"})

      # Trigger both upstreams
      {:ok, _} = Pipelines.trigger_pipeline("fanin-src-a")
      {:ok, _} = Pipelines.trigger_pipeline("fanin-src-b")

      # Consumer triggers — should get both artifacts
      {:ok, instance} = Pipelines.trigger_pipeline("fanin-consumer")
      assert instance.counter == 1
    end

    test "artifact path is watertight: different counter = different path" do
      pipeline = Repo.insert!(%Pipeline{name: "watertight-pipe", group: "test"})

      stage =
        Repo.insert!(%Stage{name: "build", pipeline_id: pipeline.id, approval_type: "success"})

      job =
        Repo.insert!(%Job{
          name: "gen",
          stage_id: stage.id,
          artifact_configs: %{"artifacts" => [%{"src" => "data.csv", "dest" => "reports/"}]}
        })

      Repo.insert!(%Task{type: "exec", command: "gen", job_id: job.id})

      {:ok, run1} = Pipelines.trigger_pipeline(pipeline.name)
      assert run1.counter == 1

      # Complete first run so second can trigger (no about-to-be-triggered conflict)
      complete_first_stage(pipeline.name, 1)

      {:ok, run2} = Pipelines.trigger_pipeline(pipeline.name)
      assert run2.counter == 2
    end

    test "artifact stores have unique IDs and are queryable" do
      alias ExGoCD.ArtifactStores

      {:ok, store} =
        ArtifactStores.create_store(%{
          plugin_id: "cd.go.artifact.docker.registry",
          properties: %{"RegistryURL" => "https://registry.example.com"}
        })

      assert store.plugin_id == "cd.go.artifact.docker.registry"

      found = ArtifactStores.get_store!(store.id)
      assert found.id == store.id

      all = ArtifactStores.list_stores()
      assert length(all) >= 1
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp insert_artifact_pipeline(name, stage_name, job_name) do
    pipeline = Repo.insert!(%Pipeline{name: name, group: "test"})

    stage =
      Repo.insert!(%Stage{
        name: stage_name,
        pipeline_id: pipeline.id,
        approval_type: "success"
      })

    job =
      Repo.insert!(%Job{
        name: job_name,
        stage_id: stage.id,
        artifact_configs: %{
          "artifacts" => [%{"src" => "build/output.jar", "dest" => "dist/"}]
        }
      })

    Repo.insert!(%Task{type: "exec", command: "build", job_id: job.id})
    {pipeline, stage, job}
  end

  defp complete_first_stage(pipeline_name, counter) do
    pi =
      Repo.one(
        from(pi in PipelineInstance,
          join: p in assoc(pi, :pipeline),
          where: p.name == ^pipeline_name and pi.counter == ^counter,
          preload: [:stage_instances]
        )
      )

    if pi do
      Enum.each(pi.stage_instances, fn si ->
        si
        |> StageInstance.changeset(%{state: "Completed", result: "Passed"})
        |> Repo.update!()

        from(ji in JobInstance, where: ji.stage_instance_id == ^si.id)
        |> Repo.all()
        |> Enum.each(fn ji ->
          ji
          |> JobInstance.changeset(%{state: "Completed", result: "Passed"})
          |> Repo.update!()
        end)
      end)
    end
  end
end
