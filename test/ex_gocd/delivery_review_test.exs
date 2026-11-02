defmodule ExGoCD.DeliveryReviewTest do
  @moduledoc """
  The delivery principles, as findings: build once, fast feedback, parallel
  feedback, as code, and a clean environment. Each test is one anti-pattern and
  the shape that replaces it.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.DeliveryReview

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

  describe "fast feedback" do
    test "a gate on the first stage makes the first answer wait for a person" do
      gated = deploy(name: "gated", materials: [dependency("build")], approval: "manual")

      assert message(review([build(), gated]), :manual_gate_first) =~
               "gates its first stage"
    end

    test "a gate after the stage that proves the build is not the problem" do
      pipeline = %{
        name: "release",
        materials: [dependency("build")],
        stages: [
          stage("verify", jobs: [job("test")]),
          stage("deploy", approval: "manual", jobs: [job("ship")])
        ]
      }

      assert :manual_gate_first not in codes(review([build(), pipeline]))
    end
  end

  describe "parallel feedback" do
    test "three commands in one job run one after another" do
      pipeline = %{
        name: "compile",
        materials: [git(app())],
        stages: [
          stage("build", jobs: [job("everything", tasks: [exec("a"), exec("b"), exec("c")])])
        ]
      }

      assert message(review([pipeline]), :serial_tasks) =~ "runs 3 commands one after another"
      assert message(review([pipeline]), :serial_tasks) =~ "as 3 jobs of one task each"
    end

    test "three jobs in the stage run at the same time" do
      pipeline = %{
        name: "compile",
        materials: [git(app())],
        stages: [
          stage("build",
            jobs: [job("unit"), job("lint"), job("types")]
          )
        ]
      }

      assert :serial_tasks not in codes(review([pipeline]))
    end
  end

  describe "as code" do
    test "a configured pipeline in no config repository exists only on this server" do
      insert_pipeline_with_jobs("hand-made", 1)

      assert message(DeliveryReview.review(), :not_in_config_repo) =~
               "exists only on this server"
    end

    test "a definition about to be created is code already" do
      assert :not_in_config_repo not in codes(review([build()]))
    end
  end

  describe "clean environment" do
    test "unpacking a fetched artifact into a dirty directory can pass on the last run's files" do
      dirty = deploy(materials: [dependency("build")], fetch: "build", clean: false)

      assert message(review([build(), dirty]), :dirty_before_fetch) =~
               "does not clean, so the previous run's files are still there"
    end

    test "a stage that cleans up first is what the fix looks like" do
      clean = deploy(materials: [dependency("build")], fetch: "build", clean: true)

      assert :dirty_before_fetch not in codes(review([build(), clean]))
    end
  end

  # ── the world ──────────────────────────────────────────────────────

  defp review(definitions), do: DeliveryReview.review(definitions, [])

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
