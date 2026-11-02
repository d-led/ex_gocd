defmodule ExGoCD.PipelineGraphTest do
  @moduledoc """
  The shapes a graph can have, and the mistakes that make one impossible: a
  dependency nobody declares, a fetch nobody publishes, and a cycle.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.{PipelineGraph, Pipelines}

  describe "a graph that works" do
    test "fan-out is not a problem: two pipelines may depend on the same build" do
      proposed = [build(), deploy("test"), deploy("production")]

      assert PipelineGraph.problems(proposed, []) == []
    end

    test "a stage and job that both exist, with artifacts, is fetchable" do
      proposed = [
        build(artifacts: [%{"src" => "target/app.jar", "dest" => "pkg"}]),
        deploy("test", fetch: %{pipeline: "build", stage: "build", job: "compile"})
      ]

      assert PipelineGraph.problems(proposed, []) == []
    end
  end

  describe "a graph that does not" do
    test "a dependency on a pipeline nobody declares is named with both ends" do
      proposed = [deploy("test", upstream: "nothing-says-this")]

      assert [%{code: :unknown_upstream, message: message}] =
               PipelineGraph.problems(proposed, [])

      assert message =~ "`test` depends on `nothing-says-this`"
      assert message =~ "neither in this graph nor configured"
    end

    test "a cycle is reported as the path that makes it" do
      proposed = [
        deploy("a", upstream: "b", stage: "build"),
        deploy("b", upstream: "a", stage: "build")
      ]

      assert [%{code: :cycle, message: message}] = PipelineGraph.problems(proposed, [])
      assert message =~ "->"
    end

    test "a cycle that closes through an already configured pipeline is found too" do
      {existing, _stage, _jobs} = insert_pipeline_with_jobs("existing", 1)

      material =
        ExGoCD.Repo.insert!(
          %ExGoCD.Pipelines.Material{}
          |> ExGoCD.Pipelines.Material.changeset(%{
            type: "dependency",
            url: "proposed",
            stage_name: "build"
          })
        )

      existing
      |> ExGoCD.Repo.preload(:materials)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:materials, [material])
      |> ExGoCD.Repo.update!()

      proposed = [deploy("proposed", upstream: "existing")]

      assert PipelineGraph.problems(proposed, Pipelines.list_pipelines())
             |> Enum.any?(&(&1.code == :cycle))
    end

    test "a fetch from a stage that is not there names the stages that are" do
      proposed = [
        build(),
        deploy("test", fetch: %{pipeline: "build", stage: "nope", job: "compile"})
      ]

      assert [%{code: :unknown_fetch_stage, message: message}] =
               PipelineGraph.problems(proposed, [])

      assert message =~ "fetches from stage `nope` of `build`"
      assert message =~ "It has `build`"
    end

    test "a fetch from a job that publishes nothing says there is nothing to take" do
      proposed = [
        build(),
        deploy("test", fetch: %{pipeline: "build", stage: "build", job: "compile"})
      ]

      assert [%{code: :unpublished_artifact, message: message}] =
               PipelineGraph.problems(proposed, [])

      assert message =~ "publishes no artifacts"
    end
  end

  # ── definitions, as `gocd_create_pipeline` reads them ─────────────

  defp build(opts \\ []) do
    %{
      name: "build",
      materials: [%{type: "git", url: "https://example.test/app.git"}],
      stages: [
        %{
          name: "build",
          approval_type: "success",
          jobs: [
            %{
              name: "compile",
              resources: [],
              artifacts: Keyword.get(opts, :artifacts, []),
              tasks: [%{type: "exec", command: "make", arguments: [], run_if: "passed"}]
            }
          ]
        }
      ]
    }
  end

  defp deploy(name, opts \\ []) do
    fetch = Keyword.get(opts, :fetch)

    tasks =
      case fetch do
        nil ->
          [%{type: "exec", command: "deploy", arguments: [], run_if: "passed"}]

        coordinates ->
          [
            %{
              type: "fetch",
              pipeline: coordinates.pipeline,
              stage: coordinates.stage,
              job: coordinates.job,
              src: "pkg/app.jar",
              dest: "lib",
              run_if: "passed"
            }
          ]
      end

    %{
      name: name,
      materials: [
        %{
          type: "dependency",
          url: Keyword.get(opts, :upstream, "build"),
          pipeline: Keyword.get(opts, :upstream, "build"),
          stage: Keyword.get(opts, :stage, "build")
        }
      ],
      stages: [
        %{
          name: "deploy",
          approval_type: "success",
          jobs: [%{name: "ship", resources: [], artifacts: [], tasks: tasks}]
        }
      ]
    }
  end
end
