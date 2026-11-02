defmodule ExGoCD.ConfigAuditTest do
  @moduledoc """
  "Will it run?" — a job runs when an agent holds the resources it asks for and
  the environments agree; every finding says which of the two gave way, and which
  agent came closest.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.{Agents, ConfigAudit, Environments, Pipelines}

  describe "a fleet that fits" do
    test "a job an agent holds the resources for, in a shared environment, is runnable" do
      agent("go-1", resources: ["docker"], environments: ["prod"])
      pipeline_with_jobs("deploy", compile: ["docker"])
      put_in_environment("prod", ["deploy"])

      assert findings() == []
      assert %{jobs: [%{runnable: ["go-1"], advice: nil}]} = ConfigAudit.fit_pipeline("deploy")
    end
  end

  describe "a job nothing can take" do
    test "names the resource no agent holds, and the agent that came closest" do
      agent("go-1", resources: ["linux"])
      pipeline_with_jobs("deploy", compile: ["linux", "docker"])

      assert [%{code: :no_agent_can_take_it, message: message}] =
               findings() |> Enum.filter(&(&1.code == :no_agent_can_take_it))

      assert message =~ "`deploy` / `build` / `compile`"
      assert message =~ "asks for `linux`, `docker`"
      assert message =~ "Closest: `go-1`, where it does not have `docker`"
    end

    test "says when there is no agent at all — once, not once per job" do
      pipeline_with_jobs("deploy", compile: ["docker"], lint: ["docker"])

      assert [%{code: :no_agents, severity: :error}] = findings()
    end

    test "says when the only agent that could take it is switched off" do
      agent("go-1", resources: ["linux"])
      agent("go-2", resources: ["linux", "docker"], disabled: true)
      pipeline_with_jobs("deploy", compile: ["docker"])

      assert [%{code: :only_disabled_agents_can_take_it, message: message}] =
               findings()
               |> Enum.filter(&(&1.code == :only_disabled_agents_can_take_it))

      assert message =~ "can run only on `go-2`, which is disabled"
      refute Enum.any?(findings(), &(&1.code == :no_agent_can_take_it))
    end
  end

  describe "environments decide as much as resources do" do
    test "an agent inside an environment takes only that environment's pipelines" do
      agent("go-1", resources: ["docker"], environments: ["staging"])
      pipeline_with_jobs("deploy", compile: ["docker"])
      put_in_environment("prod", ["deploy"])

      assert %{jobs: [%{runnable: [], blocked: [%{because: because}]}]} =
               ConfigAudit.fit_pipeline("deploy")

      assert because == ["it is in `staging` and the pipeline is in `prod`"]
    end

    test "a pipeline in no environment is taken only by agents in none" do
      agent("go-1", resources: ["docker"], environments: ["prod"])
      pipeline_with_jobs("deploy", compile: ["docker"])

      assert %{jobs: [%{verdict: verdict, advice: advice}]} = ConfigAudit.fit_pipeline("deploy")

      assert verdict =~ "it is in `prod` and the pipeline is in no environment"
      assert advice =~ "assign it to one"
    end

    test "putting both in the same environment makes it runnable" do
      agent("go-1", resources: ["docker"], environments: ["prod"])
      pipeline_with_jobs("deploy", compile: ["docker"])
      put_in_environment("prod", ["deploy"])

      assert %{jobs: [%{runnable: ["go-1"]}]} = ConfigAudit.fit_pipeline("deploy")
      assert findings() == []
    end
  end

  describe "resources written as parameters" do
    test "a defined parameter is read as its value before the agent is compared" do
      agent("go-1", resources: ["docker"])
      pipeline = pipeline_with_jobs("deploy", compile: ["\#{runtime}"])
      {:ok, _} = Pipelines.update_pipeline(pipeline, %{parameters: %{"runtime" => "docker"}})

      assert %{jobs: [%{runnable: ["go-1"], resources: ["docker"]}]} =
               ConfigAudit.fit_pipeline("deploy")
    end

    test "an undefined one is a warning rather than a resource nobody can have" do
      agent("go-1", resources: ["docker"])
      pipeline_with_jobs("deploy", compile: ["\#{runtime}"])

      assert [%{code: :undefined_parameter, message: message}] =
               findings() |> Enum.filter(&(&1.code == :undefined_parameter))

      assert message =~ "asks for the resource `\#{runtime}`"
      assert message =~ "no parameter defines it"
    end
  end

  describe "a pipeline made of a template's stages" do
    test "is checked through the jobs the template defines" do
      {:ok, template} = Pipelines.create_template(%{name: "go-build"})
      {:ok, stage} = Pipelines.create_stage(%{name: "tpl", template_id: template.id})

      {:ok, _job} =
        Pipelines.create_job(%{name: "compile", stage_id: stage.id, resources: ["docker"]})

      insert_pipeline("uses-template", template_id: template.id)
      agent("go-1", resources: ["docker"])

      assert %{jobs: [%{stage: "tpl", job: "compile", runnable: ["go-1"]}]} =
               ConfigAudit.fit_pipeline("uses-template")
    end
  end

  describe "an elastic job" do
    test "is the elastic scheduler's business, so no physical agent is missing" do
      agent("go-1", resources: ["linux"])
      pipeline_with_jobs("deploy", compile: [])

      job = Pipelines.get_pipeline_by_name("deploy") |> hd_stage_job()
      {:ok, _} = Pipelines.update_job(job, %{elastic_profile_id: "big-machine"})

      codes = findings() |> Enum.map(& &1.code)

      refute :no_agent_can_take_it in codes
      assert ConfigAudit.report().summary.elastic_jobs == 1
      assert [%{verdict: verdict}] = ConfigAudit.fit_pipeline("deploy").jobs
      assert verdict =~ "elastic profile `big-machine`"
    end
  end

  # ── the world ──────────────────────────────────────────────────────

  defp findings, do: ConfigAudit.report().findings

  defp agent(hostname, opts) do
    {:ok, agent} =
      Agents.register_agent(%{
        uuid: Ecto.UUID.generate(),
        hostname: hostname,
        resources: Keyword.get(opts, :resources, []),
        environments: Keyword.get(opts, :environments, [])
      })

    if Keyword.get(opts, :disabled, false) do
      {:ok, disabled} = Agents.update_agent(agent, %{disabled: true})
      disabled
    else
      agent
    end
  end

  defp pipeline_with_jobs(name, jobs), do: insert_pipeline_with_resources(name, jobs)

  defp put_in_environment(environment_name, pipeline_names) do
    {:ok, _environment} = Environments.create_environment(%{name: environment_name})
    Enum.each(pipeline_names, &Environments.add_pipeline_to_environment(environment_name, &1))
  end

  defp hd_stage_job(pipeline), do: pipeline.stages |> hd() |> Map.get(:jobs) |> hd()
end
