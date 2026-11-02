defmodule ExGoCD.Mcp.Tools.PipelineGraphCreateTest do
  @moduledoc """
  Creating a graph rather than a pipeline: fan-out in one call, the build passed
  to the deploys as an artifact, and a cycle refused before anything is written.
  """

  use ExGoCD.DataCase, async: false

  alias ExGoCD.{Accounts, Pipelines}
  alias ExGoCD.Mcp.Tools, as: Registry

  @admin %{
    user: %Accounts.User{username: "admin", roles: ["admin"], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

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

  describe "a fan-out graph" do
    test "is created in one call, and its shape is named back" do
      assert {:ok, %{text: text, structured: structured}} =
               Registry.call("gocd_create_pipeline", %{"pipelines" => graph()}, @admin)

      assert text =~ "3 pipelines created"
      assert text =~ "`build` -> `test`, `production`"
      assert text =~ "fan-out from `build` to 2 pipelines"

      assert [
               %{"from" => "build", "to" => "test"},
               %{"from" => "build", "to" => "production"}
             ] = structured["edges"]
    end

    test "the dependency names the upstream stage, so the deploy waits for the build" do
      {:ok, _} = Registry.call("gocd_create_pipeline", %{"pipelines" => graph()}, @admin)

      deploy = Pipelines.get_pipeline_by_name("test")

      assert [%{type: "dependency", url: "build"} = material] = deploy.materials
      assert material.type_specific_config == %{"stage_name" => "build"}
    end

    test "the build publishes an artifact and the deploy takes that same build" do
      {:ok, _} = Registry.call("gocd_create_pipeline", %{"pipelines" => graph()}, @admin)

      build_job = Pipelines.get_pipeline_by_name("build") |> first_job()
      deploy_job = Pipelines.get_pipeline_by_name("test") |> first_job()

      assert %{"artifacts" => [%{"src" => "target/app.jar", "dest" => "pkg", "type" => "build"}]} =
               build_job.artifact_configs

      assert [%{type: "fetch", arguments: ["build", "build", "compile", "pkg/app.jar", "lib"]}] =
               deploy_job.tasks
    end
  end

  describe "a graph that cannot work" do
    test "a cycle is refused, and nothing at all is created" do
      cyclic = [deploy("a", "b"), deploy("b", "a")]

      assert {:error, message} =
               Registry.call("gocd_create_pipeline", %{"pipelines" => cyclic}, @admin)

      assert message =~ "depend on each other"
      assert Pipelines.get_pipeline_by_name("a") == nil
      assert Pipelines.get_pipeline_by_name("b") == nil
    end

    test "one bad pipeline leaves none of them behind" do
      broken = [build(), %{"name" => "test", "stages" => []}]

      assert {:error, message} =
               Registry.call("gocd_create_pipeline", %{"pipelines" => broken}, @admin)

      assert message =~ "`stages` must be a non-empty list"
      assert Pipelines.get_pipeline_by_name("build") == nil
    end
  end

  describe "checking before creating" do
    test "the same graph can be validated without being created" do
      assert {:ok, %{text: text, structured: structured}} =
               Registry.call("gocd_validate_pipeline", %{"pipelines" => graph()}, @admin)

      assert text =~ "3 pipeline(s)"
      assert structured["problems"] == []
      assert structured["pipelines"] == ["build", "test", "production"]
      assert Pipelines.get_pipeline_by_name("build") == nil
    end

    test "a fetch of something nobody publishes is reported before it is asked for" do
      unpublishable = [build() |> forget_artifacts(), deploy("test", "build")]

      assert {:ok, %{text: text, structured: structured}} =
               Registry.call(
                 "gocd_validate_pipeline",
                 %{"pipelines" => unpublishable},
                 @admin
               )

      assert text =~ "publishes no artifacts"
      assert [%{"code" => "unpublished_artifact"}] = structured["problems"]
      assert structured["will_run"] == false
    end
  end

  # ── the graph ──────────────────────────────────────────────────────

  defp graph, do: [build(), deploy("test", "build"), deploy("production", "build")]

  defp build do
    %{
      "name" => "build",
      "materials" => [%{"type" => "git", "url" => "https://example.test/app.git"}],
      "stages" => [
        %{
          "name" => "build",
          "jobs" => [
            %{
              "name" => "compile",
              "resources" => [],
              "artifacts" => [%{"src" => "target/app.jar", "dest" => "pkg"}],
              "tasks" => [%{"command" => "make"}]
            }
          ]
        }
      ]
    }
  end

  defp forget_artifacts(definition) do
    update_in(definition["stages"], fn stages ->
      Enum.map(stages, fn stage ->
        update_in(stage["jobs"], fn jobs ->
          Enum.map(jobs, &Map.delete(&1, "artifacts"))
        end)
      end)
    end)
  end

  defp deploy(name, upstream) do
    %{
      "name" => name,
      "materials" => [%{"type" => "dependency", "pipeline" => upstream, "stage" => "build"}],
      "stages" => [
        %{
          "name" => "deploy",
          "jobs" => [
            %{
              "name" => "ship",
              "tasks" => [
                %{
                  "type" => "fetch",
                  "pipeline" => "build",
                  "stage" => "build",
                  "job" => "compile",
                  "src" => "pkg/app.jar",
                  "dest" => "lib"
                }
              ]
            }
          ]
        }
      ]
    }
  end

  defp first_job(pipeline), do: pipeline.stages |> hd() |> Map.get(:jobs) |> hd()
end
