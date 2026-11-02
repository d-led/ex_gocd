defmodule ExGoCD.Mcp.Tools.PipelineConfigTest do
  @moduledoc """
  Authoring a pipeline: the tree is built in order, a refusal names the stage it
  was about, and a failure half-way through leaves nothing behind.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.{Accounts, AuditLog, Pipelines}
  alias ExGoCD.Mcp.Tools.PipelineConfig, as: Tools

  @admin %{
    user: %ExGoCD.Accounts.User{username: "admin", roles: ["admin"], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  @viewer %{@admin | user: %ExGoCD.Accounts.User{username: "viewer", roles: [], status: "Active"}}

  setup do
    # An administrator exists, so the permission checks have something to check.
    {:ok, _} =
      Accounts.create_user(%{
        username: "admin",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    :ok
  end

  describe "gocd_create_pipeline" do
    test "builds the stages, jobs and tasks it was given, in the order it was given them" do
      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_create_pipeline", %{"definition" => definition()}, @admin)

      assert structured["name"] == "authored"
      assert structured["group"] == "ci"

      assert [
               %{"name" => "build", "approval_type" => "success", "jobs" => ["compile", "lint"]},
               %{"name" => "ship", "approval_type" => "manual", "jobs" => ["deploy"]}
             ] = structured["stages"]

      assert structured["materials"] == [
               %{"type" => "git", "url" => "https://example.test/app.git"}
             ]

      assert text =~ "2 stage(s), 3 job(s), 1 material(s)"

      pipeline = Pipelines.get_pipeline_by_name("authored")
      assert pipeline.group == "ci"
      assert pipeline.stages |> Enum.map(& &1.name) |> Enum.sort() == ["build", "ship"]
      assert [%{command: "make", arguments: ["test"]}] = compile_tasks(pipeline)
    end

    test "a refused stage rolls the whole pipeline back" do
      duplicated = %{definition() | "stages" => [stage("build"), stage("build")]}

      assert {:error, message} =
               Tools.call("gocd_create_pipeline", %{"definition" => duplicated}, @admin)

      assert message =~ "Stage 'build'"
      assert Pipelines.get_pipeline_by_name("authored") == nil
    end

    test "a definition with no stages is refused before anything is written" do
      assert {:error, message} =
               Tools.call(
                 "gocd_create_pipeline",
                 %{"definition" => %{"name" => "half"}},
                 @admin
               )

      assert message =~ "`stages` must be a non-empty list"
      assert Pipelines.get_pipeline_by_name("half") == nil
    end

    test "a job with no task is refused, and says why" do
      definition = %{
        "name" => "pointless",
        "stages" => [%{"name" => "build", "jobs" => [%{"name" => "idle", "tasks" => []}]}]
      }

      assert {:error, message} =
               Tools.call("gocd_create_pipeline", %{"definition" => definition}, @admin)

      assert message =~ "at least one task"
    end

    test "a name that exists is refused, and points at what to use instead" do
      insert_pipeline("authored")

      assert {:error, message} =
               Tools.call("gocd_create_pipeline", %{"definition" => definition()}, @admin)

      assert message =~ "already exists"
      assert message =~ "gocd_update_pipeline"
    end

    test "is an administrator's act", %{} do
      assert {:error, message} =
               Tools.call("gocd_create_pipeline", %{"definition" => definition()}, @viewer)

      assert message =~ "Only an administrator"
      assert Pipelines.get_pipeline_by_name("authored") == nil
    end
  end

  describe "gocd_update_pipeline" do
    test "changes the settings it was given and leaves the rest alone" do
      insert_pipeline("editable", group: "old", label_template: "${COUNT}")

      assert {:ok, %{structured: structured}} =
               Tools.call(
                 "gocd_update_pipeline",
                 %{"name" => "editable", "group" => "ci", "label_template" => "v${COUNT}"},
                 @admin
               )

      assert structured["group"] == "ci"
      assert structured["label_template"] == "v${COUNT}"

      pipeline = Pipelines.get_pipeline_by_name("editable")
      assert pipeline.group == "ci"
      assert pipeline.label_template == "v${COUNT}"
      assert pipeline.lock_behavior == "none"
    end

    test "the change is recorded with the fields it touched" do
      insert_pipeline("editable")

      assert {:ok, _} =
               Tools.call(
                 "gocd_update_pipeline",
                 %{"name" => "editable", "paused" => true},
                 @admin
               )

      assert [entry | _] = AuditLog.search(%{action: "config.changed"})
      assert entry.actor == "admin"

      assert entry.details["payload"]["diff"] == %{
               "action" => "updated",
               "fields" => ["paused"]
             }
    end

    test "says when there is nothing to change" do
      insert_pipeline("editable")

      assert {:error, message} =
               Tools.call("gocd_update_pipeline", %{"name" => "editable"}, @admin)

      assert message =~ "Nothing to change"
    end

    test "a pipeline that does not exist is named as such" do
      assert Tools.call("gocd_update_pipeline", %{"name" => "ghost", "group" => "ci"}, @admin) ==
               {:error, "Pipeline 'ghost' not found."}
    end
  end

  describe "gocd_delete_pipeline" do
    test "asks for a confirmation, and changes nothing without it" do
      insert_pipeline("doomed")

      assert {:error, message} =
               Tools.call("gocd_delete_pipeline", %{"name" => "doomed"}, @admin)

      assert message =~ "confirm: true"
      assert Pipelines.get_pipeline_by_name("doomed")
    end

    test "deletes the pipeline and its run history when confirmed" do
      insert_pipeline("doomed")
      instance = insert_pipeline_instance_by_name("doomed", 1, DateTime.utc_now())
      insert_stage_instance(instance.id, "build")

      assert {:ok, %{structured: %{"deleted" => true}}} =
               Tools.call(
                 "gocd_delete_pipeline",
                 %{"name" => "doomed", "confirm" => true},
                 @admin
               )

      assert Pipelines.get_pipeline_by_name("doomed") == nil
      assert Pipelines.get_pipeline_instance("doomed", 1) == nil
    end
  end

  # ── the definition under test ──────────────────────────────────────

  defp definition do
    %{
      "name" => "authored",
      "group" => "ci",
      "label_template" => "v${COUNT}",
      "materials" => [
        %{"type" => "git", "url" => "https://example.test/app.git", "branch" => "main"}
      ],
      "stages" => [
        %{
          "name" => "build",
          "jobs" => [
            %{
              "name" => "compile",
              "resources" => ["linux"],
              "tasks" => [%{"command" => "make", "arguments" => ["test"]}]
            },
            %{
              "name" => "lint",
              "tasks" => [%{"command" => "mix", "arguments" => ["credo"]}]
            }
          ]
        },
        %{
          "name" => "ship",
          "approval_type" => "manual",
          "jobs" => [%{"name" => "deploy", "tasks" => [%{"command" => "./deploy.sh"}]}]
        }
      ]
    }
  end

  defp stage(name) do
    %{"name" => name, "jobs" => [%{"name" => "job-#{name}", "tasks" => [%{"command" => "true"}]}]}
  end

  defp compile_tasks(pipeline) do
    pipeline.stages
    |> Enum.find(&(&1.name == "build"))
    |> Map.fetch!(:jobs)
    |> Enum.find(&(&1.name == "compile"))
    |> Map.fetch!(:tasks)
  end
end
