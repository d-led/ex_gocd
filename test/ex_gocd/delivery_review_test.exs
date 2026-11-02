defmodule ExGoCD.DeliveryReviewTest do
  @moduledoc """
  The delivery principles, as findings: build once, fast feedback, parallel
  feedback, as code, and a clean environment. Each test is one anti-pattern and
  the shape that replaces it.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.{DeliveryReview, Pipelines}

  describe "build once" do
    test "a deploy that checks out the build's repository can rebuild what it built" do
      findings = review([build(), deploy(materials: [git(app()), dependency("build")])])

      assert message(findings, :rebuilds_upstream) =~
               "depends on `build` and also checks out `https://example.test/app.git`"

      assert message(findings, :rebuilds_upstream) =~ "fetch `build`'s artifact instead"
    end

    test "a deploy that only takes the build's artifact is not nagged" do
      findings = review([build(), deploy(materials: [dependency("build")], fetch: "build")])

      assert codes(findings) == []
    end

    test "a pipeline others depend on has to publish something" do
      findings = review([build(publishes: false), deploy(materials: [dependency("build")])])

      assert message(findings, :nothing_to_fetch) =~ "is depended on by `deploy`"
      assert message(findings, :nothing_to_fetch) =~ "publishes no artifacts"
    end

    test "a fetch from something this pipeline does not depend on has no revision guarantee" do
      findings = review([build(), deploy(materials: [], fetch: "build")])

      assert message(findings, :fetch_without_dependency) =~
               "fetches from `build` without depending on it"
    end
  end

  describe "the shape the fleet can run" do
    test "three docker jobs and one docker agent is a queue, however it is drawn" do
      pipeline = three_docker_jobs()

      findings = DeliveryReview.review([pipeline], [], %{agents: [agent("go-1", ["docker"])]})

      assert message(findings, :narrower_than_the_stage) =~
               "has 3 jobs but at most 1 agents can take them at the same time"
    end

    test "three docker jobs and three docker agents is what parallel looks like" do
      pipeline = three_docker_jobs()

      agents = [agent("go-1", ["docker"]), agent("go-2", ["docker"]), agent("go-3", ["docker"])]

      assert :narrower_than_the_stage not in codes(
               DeliveryReview.review([pipeline], [], %{agents: agents})
             )
    end

    test "a fleet of one agent says so once, not once per stage" do
      findings =
        DeliveryReview.review([build(), deploy(materials: [dependency("build")])], [], %{
          agents: [agent("go-1", ["docker"])]
        })

      assert [finding] = Enum.filter(findings, &(&1.code == :one_agent_fleet))
      assert finding.message =~ "every parallel stage"
    end
  end

  describe "a deploy without an environment" do
    test "runs on the default pool and has nowhere to be promoted through" do
      {pipeline, _stage, _jobs} = insert_pipeline_with_jobs("deploy", 1)
      attach_dependency(pipeline, "build")

      findings = DeliveryReview.review([], Pipelines.list_pipelines(), %{environments: %{}})

      assert message(findings, :deploy_without_environment) =~
               "deploys but belongs to no environment"
    end
  end

  # ── the world ──────────────────────────────────────────────────────

  defp review(definitions), do: DeliveryReview.review(definitions, [])

  defp agent(hostname, resources) do
    %{uuid: hostname, hostname: hostname, resources: resources, environments: [], disabled: false}
  end

  defp three_docker_jobs do
    %{
      name: "test",
      materials: [dependency("build")],
      stages: [
        stage("test",
          jobs: [
            job("unit", resources: ["docker"]),
            job("integration", resources: ["docker"]),
            job("acceptance", resources: ["docker"])
          ]
        )
      ]
    }
  end

  defp attach_dependency(pipeline, upstream) do
    material =
      ExGoCD.Repo.insert!(
        %ExGoCD.Pipelines.Material{}
        |> ExGoCD.Pipelines.Material.changeset(%{type: "dependency", url: upstream})
      )

    pipeline
    |> ExGoCD.Repo.preload(:materials)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:materials, [material])
    |> ExGoCD.Repo.update!()
  end

  defp codes(findings), do: Enum.map(findings, & &1.code)

  defp message(findings, code) do
    case Enum.find(findings, &(&1.code == code)) do
      nil -> flunk("expected a #{code} finding, got #{inspect(codes(findings))}")
      finding -> finding.message
    end
  end

  defp build(opts \\ []) do
    %{
      name: "build",
      materials: [git(app())],
      stages: [
        stage("build",
          jobs: [
            job("compile",
              artifacts:
                if(Keyword.get(opts, :publishes, true),
                  do: [%{"type" => "build", "src" => "target/app.jar", "dest" => "pkg"}],
                  else: []
                )
            )
          ]
        )
      ]
    }
  end

  defp deploy(opts) do
    tasks =
      case Keyword.get(opts, :fetch) do
        nil -> [exec("deploy")]
        from -> [fetch(from)]
      end

    %{
      name: Keyword.get(opts, :name, "deploy"),
      materials: Keyword.get(opts, :materials, []),
      stages: [
        stage(Keyword.get(opts, :stage_name, "deploy"),
          approval: Keyword.get(opts, :approval, "success"),
          clean: Keyword.get(opts, :clean, true),
          jobs: [job("ship", tasks: tasks)]
        )
      ]
    }
  end

  defp stage(name, opts) do
    %{
      name: name,
      approval_type: Keyword.get(opts, :approval, "success"),
      clean_working_directory: Keyword.get(opts, :clean, true),
      jobs: Keyword.get(opts, :jobs, [job("compile")])
    }
  end

  defp job(name, opts \\ []) do
    %{
      name: name,
      artifacts: Keyword.get(opts, :artifacts, []),
      resources: Keyword.get(opts, :resources, []),
      tasks: Keyword.get(opts, :tasks, [exec("make")])
    }
  end

  defp exec(command), do: %{type: "exec", command: command, arguments: [], run_if: "passed"}

  defp fetch(from) do
    %{
      type: "fetch",
      pipeline: from,
      stage: "build",
      job: "compile",
      src: "pkg/app.jar",
      dest: "lib",
      run_if: "passed"
    }
  end

  defp dependency(upstream),
    do: %{type: "dependency", url: upstream, pipeline: upstream, stage: "build"}

  defp git(url), do: %{type: "git", url: url}

  defp app, do: "https://example.test/app.git"
end
