defmodule ExGoCDWeb.CCTrayControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Repo
  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance, Stage, StageInstance}

  import ExGoCD.PipelinesFixtures,
    only: [insert_pipeline: 2, insert_stage: 2, insert_pipeline_instance: 2, insert_stage_instance: 3]

  setup do
    # Ensure clean state
    Repo.delete_all(StageInstance)
    Repo.delete_all(PipelineInstance)
    Repo.delete_all(Stage)
    Repo.delete_all(Pipeline)
    :ok
  end

  describe "GET /go/cctray.xml" do
    test "returns valid XML with Projects root when no pipelines exist", %{conn: conn} do
      conn = get(conn, "/go/cctray.xml")

      assert conn.status == 200
      assert conn.resp_body =~ "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
      assert conn.resp_body =~ "<Projects>"
      assert conn.resp_body =~ "</Projects>"
      # No Project elements when there are no pipeline stages
      refute conn.resp_body =~ "<Project "
    end

    test "reports each stage of each pipeline as a Project element", %{conn: conn} do
      pipeline = insert_pipeline("my-app", group: "default")
      insert_stage(pipeline.id, "build")
      insert_stage(pipeline.id, "test")
      pi = insert_pipeline_instance(pipeline.id, 5)
      insert_stage_instance(pi.id, "build", counter: 1, state: "Completed", result: "Passed")
      insert_stage_instance(pi.id, "test", counter: 1, state: "Completed", result: "Failed")

      conn = get(conn, "/go/cctray.xml")

      assert conn.status == 200
      assert conn.resp_body =~ ~s(name="my-app :: build")
      assert conn.resp_body =~ ~s(name="my-app :: test")
      assert conn.resp_body =~ ~s(lastBuildStatus="Success")
      assert conn.resp_body =~ ~s(lastBuildStatus="Failure")
      assert conn.resp_body =~ ~s(lastBuildLabel="5")
      assert conn.resp_body =~ ~s(activity="Sleeping")
      assert conn.resp_body =~ ~s(webUrl="/go/pipelines/my-app/5/build/5")
    end

    test "maps stage statuses to CCTray statuses correctly", %{conn: conn} do
      pipeline = insert_pipeline("status-test", group: "default")
      insert_stage(pipeline.id, "s1")
      pi = insert_pipeline_instance(pipeline.id, 1)

      # Passed → Success
      insert_stage_instance(pi.id, "s1", counter: 1, state: "Completed", result: "Passed")
      conn = get(conn, "/go/cctray.xml")
      assert conn.resp_body =~ ~s(lastBuildStatus="Success")

      # Delete and re-insert: Failed → Failure
      Repo.delete_all(StageInstance)
      insert_stage_instance(pi.id, "s1", counter: 1, state: "Completed", result: "Failed")
      conn = get(conn, "/go/cctray.xml")
      assert conn.resp_body =~ ~s(lastBuildStatus="Failure")

      # Cancelled → Exception
      Repo.delete_all(StageInstance)
      insert_stage_instance(pi.id, "s1", counter: 1, state: "Completed", result: "Cancelled")
      conn = get(conn, "/go/cctray.xml")
      assert conn.resp_body =~ ~s(lastBuildStatus="Exception")
    end

    test "shows Building activity for active stages", %{conn: conn} do
      pipeline = insert_pipeline("active-pipe", group: "default")
      insert_stage(pipeline.id, "deploy")
      pi = insert_pipeline_instance(pipeline.id, 3)
      insert_stage_instance(pi.id, "deploy", counter: 1, state: "Building", result: "Unknown")

      conn = get(conn, "/go/cctray.xml")

      assert conn.resp_body =~ ~s(activity="Building")
    end

    test "escapes XML special characters in names", %{conn: conn} do
      pipeline = insert_pipeline("foo & bar", group: "default")
      insert_stage(pipeline.id, "build < test")
      pi = insert_pipeline_instance(pipeline.id, 1)
      insert_stage_instance(pi.id, "build < test", counter: 1, state: "Completed", result: "Passed")

      conn = get(conn, "/go/cctray.xml")

      assert conn.resp_body =~ "foo &amp; bar"
      assert conn.resp_body =~ "build &lt; test"
    end

    test "includes webUrl for each project", %{conn: conn} do
      pipeline = insert_pipeline("web-url-pipe", group: "group1")
      insert_stage(pipeline.id, "stage1")
      pi = insert_pipeline_instance(pipeline.id, 42)
      insert_stage_instance(pi.id, "stage1", counter: 1, state: "Completed", result: "Passed")

      conn = get(conn, "/go/cctray.xml")

      assert conn.resp_body =~ ~s(webUrl="/go/pipelines/web-url-pipe/42/stage1/42")
    end
  end

end
