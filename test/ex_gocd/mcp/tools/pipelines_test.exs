defmodule ExGoCD.Mcp.Tools.PipelinesTest do
  @moduledoc """
  What the pipeline tools say about a configured pipeline and its runs, read
  from the same context the dashboard and the JSON API read.
  """

  use ExGoCD.DataCase, async: true

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Mcp.Tools.{Pipelines, Stages}

  @ctx %{
    user: %ExGoCD.Accounts.User{username: "reader", roles: [], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  describe "gocd_list_pipelines" do
    test "counts what it found and shows the stages in the order they run" do
      insert_pipeline_with_two_stages("build-app")
      insert_pipeline("docs")

      assert {:ok, %{text: text, structured: structured}} =
               Pipelines.call("gocd_list_pipelines", %{}, @ctx)

      assert structured["matched"] == 2
      assert text =~ "build-app"
      assert text =~ "stage1 → stage2"
    end

    test "narrows to a group and to words in the name" do
      insert_pipeline("build-app", group: "ci")
      insert_pipeline("docs", group: "docs")

      assert {:ok, %{structured: %{"matched" => 1}}} =
               Pipelines.call("gocd_list_pipelines", %{"group" => "ci"}, @ctx)

      assert {:ok, %{structured: %{"matched" => 1}}} =
               Pipelines.call("gocd_list_pipelines", %{"query" => "doc"}, @ctx)
    end
  end

  describe "gocd_describe_pipeline" do
    test "names the materials, stages, jobs and tasks it is made of" do
      insert_pipeline_with_two_stages("build-app")

      assert {:ok, %{structured: structured}} =
               Pipelines.call("gocd_describe_pipeline", %{"name" => "build-app"}, @ctx)

      assert structured["group"] == "test"
      assert [material] = structured["materials"]
      assert material["url"] == "https://github.com/test/build-app.git"

      assert [first, second] = structured["stages"]
      assert first["name"] == "stage1"
      assert second["approval_type"] == "manual"
      assert [%{"name" => "job1", "tasks" => ["exec: echo 1"]}] = first["jobs"]
    end

    test "never shows a secure variable's value" do
      pipeline =
        insert_pipeline("secure-pipeline")
        |> Ecto.Changeset.change(
          environment_variables: %{"PLAIN" => "visible"},
          secure_variables: %{"TOKEN" => %{"value" => "secret", "secure" => true}}
        )
        |> Repo.update!()

      assert {:ok, %{text: text, structured: structured}} =
               Pipelines.call("gocd_describe_pipeline", %{"name" => pipeline.name}, @ctx)

      assert structured["environment_variables"] == %{"PLAIN" => "visible", "TOKEN" => "(secure)"}
      refute text =~ "secret"
    end

    test "says a pipeline it cannot find is missing" do
      assert Pipelines.call("gocd_describe_pipeline", %{"name" => "nope"}, @ctx) ==
               {:error, "Pipeline 'nope' not found."}
    end
  end

  describe "gocd_pipeline_status" do
    test "a paused pipeline is not schedulable, and says who paused it and why" do
      pipeline = insert_pipeline("paused-app")
      {:ok, _} = ExGoCD.Pipelines.pause_pipeline(pipeline.name, "ops", "freezing")

      assert {:ok, %{structured: structured}} =
               Pipelines.call("gocd_pipeline_status", %{"name" => "paused-app"}, @ctx)

      assert structured["paused"] == true
      assert structured["schedulable"] == false
      assert structured["paused_by"] == "ops"
      assert structured["paused_cause"] == "freezing"
    end
  end

  describe "gocd_pipeline_history and gocd_pipeline_instance" do
    setup do
      insert_pipeline("history-app")

      instance =
        insert_pipeline_instance_by_name("history-app", 1, DateTime.utc_now())

      stage = insert_stage_instance(instance.id, "build", state: "Completed", result: "Passed")
      insert_job_instance(stage.id, "compile", DateTime.utc_now(), DateTime.utc_now())

      {:ok, instance: instance}
    end

    test "history counts the runs and shows how each stage ended" do
      assert {:ok, %{text: text, structured: structured}} =
               Pipelines.call("gocd_pipeline_history", %{"name" => "history-app"}, @ctx)

      assert structured["total"] == 1
      assert text =~ "build:Passed"
    end

    test "one run is answered whole, with its jobs" do
      assert {:ok, %{structured: structured}} =
               Pipelines.call(
                 "gocd_pipeline_instance",
                 %{"name" => "history-app", "counter" => 1},
                 @ctx
               )

      assert structured["counter"] == 1

      assert [%{"name" => "build", "jobs" => [%{"name" => "compile", "state" => "Completed"}]}] =
               structured["stages"]
    end

    test "a run that does not exist is named as such" do
      assert Pipelines.call(
               "gocd_pipeline_instance",
               %{"name" => "history-app", "counter" => 9},
               @ctx
             ) == {:error, "Run #9 of 'history-app' not found."}
    end

    test "one stage of that run is answered with its jobs" do
      assert {:ok, %{structured: structured}} =
               Stages.call(
                 "gocd_stage",
                 %{
                   "pipeline" => "history-app",
                   "counter" => 1,
                   "stage" => "build",
                   "stage_counter" => 1
                 },
                 @ctx
               )

      assert structured["result"] == "Passed"
      assert [%{"name" => "compile"}] = structured["jobs"]
    end
  end
end
