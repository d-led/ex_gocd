defmodule ExGoCD.Mcp.Tools.AuditTest do
  @moduledoc """
  The "will it run?" family: the configuration's dead ends, one pipeline's agents,
  and the same question about a definition that does not exist yet.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.{Accounts, Agents, Pipelines}
  alias ExGoCD.Mcp.Tools, as: Registry
  alias ExGoCD.Mcp.Tools.Audit, as: Tools

  @reader %{
    user: %Accounts.User{username: "reader", roles: [], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  @admin %{@reader | user: %Accounts.User{username: "admin", roles: ["admin"], status: "Active"}}

  setup do
    {:ok, _} =
      Accounts.create_user(%{
        username: "admin",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    :ok
  end

  describe "gocd_audit_config" do
    test "names the job that will not run and counts it" do
      agent("go-1", resources: ["linux"])
      pipeline_with_jobs("deploy", compile: ["docker"])

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_audit_config", %{}, @reader)

      assert text =~ "Will not run (1):"
      assert text =~ "`deploy` / `build` / `compile`"
      assert text =~ "it does not have `docker`"
      assert structured["summary"]["jobs_without_an_agent"] == 1

      assert [%{"code" => "no_agent_can_take_it", "severity" => "error"}] =
               Enum.filter(structured["findings"], &(&1["code"] == "no_agent_can_take_it"))
    end

    test "says so plainly when everything fits" do
      agent("go-1", resources: ["docker"])
      pipeline_with_jobs("deploy", compile: ["docker"])

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_audit_config", %{}, @reader)

      assert text =~ "Every job has an agent that can take it."
      assert structured["findings"] == []
      assert structured["summary"]["errors"] == 0
    end
  end

  describe "gocd_who_can_run" do
    test "says which agents can take a job and what the others lack" do
      agent("go-1", resources: ["docker"])
      agent("go-2", resources: ["linux"])
      pipeline_with_jobs("deploy", compile: ["docker"])

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_who_can_run", %{"pipeline" => "deploy"}, @reader)

      assert text =~ "`build` / `compile`: 1 agent(s) can take it: go-1"

      assert [%{"can_run" => ["go-1"], "cannot_run" => [%{"agent" => "go-2"}]}] =
               structured["jobs"]
    end

    test "an unknown pipeline is a refusal that says where the names are" do
      assert {:error, message} = Tools.call("gocd_who_can_run", %{"pipeline" => "nope"}, @reader)
      assert message =~ "Pipeline 'nope' not found"
      assert message =~ "gocd_list_pipelines"
    end

    test "a stage narrows the answer to the jobs in it" do
      agent("go-1", resources: ["docker"])
      pipeline = insert_pipeline("deploy")
      {:ok, build} = Pipelines.create_stage(%{name: "build", pipeline_id: pipeline.id})
      {:ok, ship} = Pipelines.create_stage(%{name: "ship", pipeline_id: pipeline.id})

      {:ok, _} =
        Pipelines.create_job(%{name: "compile", stage_id: build.id, resources: ["docker"]})

      {:ok, _} =
        Pipelines.create_job(%{name: "release", stage_id: ship.id, resources: ["docker"]})

      assert {:ok, %{structured: structured}} =
               Tools.call(
                 "gocd_who_can_run",
                 %{"pipeline" => "deploy", "stage" => "ship"},
                 @reader
               )

      assert [%{"stage" => "ship", "job" => "release"}] = structured["jobs"]
    end
  end

  describe "gocd_validate_pipeline" do
    test "answers about a pipeline that does not exist, and creates nothing" do
      agent("go-1", resources: ["linux"])

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call(
                 "gocd_validate_pipeline",
                 %{"definition" => definition(["docker"])},
                 @reader
               )

      assert text =~ "Nothing was created."
      assert text =~ "no agent can take it"
      assert text =~ "it does not have `docker`"
      assert structured["will_run"] == false
      assert Pipelines.get_pipeline_by_name("checked") == nil
    end

    test "says a definition would run when an agent can take every job" do
      agent("go-1", resources: ["docker"])

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call(
                 "gocd_validate_pipeline",
                 %{"definition" => definition(["docker"])},
                 @reader
               )

      assert text =~ "1 agent(s) can take it: go-1"
      assert structured["will_run"] == true
    end

    test "a definition it cannot read is refused the way create would refuse it" do
      assert {:error, message} =
               Tools.call(
                 "gocd_validate_pipeline",
                 %{"definition" => %{"name" => "checked", "stages" => []}},
                 @reader
               )

      assert message =~ "`stages` must be a non-empty list"
    end
  end

  describe "gocd_create_pipeline" do
    test "says whether the pipeline it just built will run" do
      agent("go-1", resources: ["linux"])

      assert {:ok, %{text: text, structured: structured}} =
               Registry.call(
                 "gocd_create_pipeline",
                 %{"definition" => definition(["docker"])},
                 @admin
               )

      assert text =~ "Will it run? Not yet"
      assert text =~ "no agent can take it"
      assert structured["will_run"]["jobs"] == 1
      assert structured["will_run"]["jobs_with_an_agent"] == 0
    end
  end

  # ── the world ──────────────────────────────────────────────────────

  defp definition(resources) do
    %{
      "name" => "checked",
      "stages" => [
        %{
          "name" => "build",
          "jobs" => [
            %{
              "name" => "compile",
              "resources" => resources,
              "tasks" => [%{"command" => "make"}]
            }
          ]
        }
      ]
    }
  end

  defp agent(hostname, opts) do
    {:ok, agent} =
      Agents.register_agent(%{
        uuid: Ecto.UUID.generate(),
        hostname: hostname,
        resources: Keyword.get(opts, :resources, []),
        environments: Keyword.get(opts, :environments, [])
      })

    agent
  end

  defp pipeline_with_jobs(name, jobs), do: insert_pipeline_with_resources(name, jobs)
end
