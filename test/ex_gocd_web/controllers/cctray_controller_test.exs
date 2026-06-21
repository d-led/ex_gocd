defmodule ExGoCDWeb.CCTrayControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Repo
  alias ExGoCD.Pipelines.{Pipeline, PipelineInstance, Stage, StageInstance}

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
      pipeline = insert_pipeline("my-app", "default")
      insert_stage_config(pipeline.id, "build")
      insert_stage_config(pipeline.id, "test")
      pi = insert_pipeline_instance(pipeline.id, 5, "5")
      insert_stage_instance(pi.id, "build", 1, "Completed", "Passed")
      insert_stage_instance(pi.id, "test", 1, "Completed", "Failed")

      conn = get(conn, "/go/cctray.xml")

      assert conn.status == 200
      assert conn.resp_body =~ ~s(name="my-app :: build")
      assert conn.resp_body =~ ~s(name="my-app :: test")
      assert conn.resp_body =~ ~s(lastBuildStatus="Success")
      assert conn.resp_body =~ ~s(lastBuildStatus="Failure")
      assert conn.resp_body =~ ~s(lastBuildLabel="5")
      assert conn.resp_body =~ ~s(activity="Sleeping")
      assert conn.resp_body =~ ~s(webUrl="/go/pipelines/my-app/5/build/1")
    end

    test "maps stage statuses to CCTray statuses correctly", %{conn: conn} do
      pipeline = insert_pipeline("status-test", "default")
      insert_stage_config(pipeline.id, "s1")
      pi = insert_pipeline_instance(pipeline.id, 1, "1")

      # Passed → Success
      insert_stage_instance(pi.id, "s1", 1, "Completed", "Passed")
      conn = get(conn, "/go/cctray.xml")
      assert conn.resp_body =~ ~s(lastBuildStatus="Success")

      # Delete and re-insert: Failed → Failure
      Repo.delete_all(StageInstance)
      insert_stage_instance(pi.id, "s1", 1, "Completed", "Failed")
      conn = get(conn, "/go/cctray.xml")
      assert conn.resp_body =~ ~s(lastBuildStatus="Failure")

      # Cancelled → Exception
      Repo.delete_all(StageInstance)
      insert_stage_instance(pi.id, "s1", 1, "Completed", "Cancelled")
      conn = get(conn, "/go/cctray.xml")
      assert conn.resp_body =~ ~s(lastBuildStatus="Exception")
    end

    test "shows Building activity for active stages", %{conn: conn} do
      pipeline = insert_pipeline("active-pipe", "default")
      insert_stage_config(pipeline.id, "deploy")
      pi = insert_pipeline_instance(pipeline.id, 3, "3")
      insert_stage_instance(pi.id, "deploy", 1, "Building", "Unknown")

      conn = get(conn, "/go/cctray.xml")

      assert conn.resp_body =~ ~s(activity="Building")
    end

    test "escapes XML special characters in names", %{conn: conn} do
      pipeline = insert_pipeline("foo & bar", "default")
      insert_stage_config(pipeline.id, "build < test")
      pi = insert_pipeline_instance(pipeline.id, 1, "1")
      insert_stage_instance(pi.id, "build < test", 1, "Completed", "Passed")

      conn = get(conn, "/go/cctray.xml")

      assert conn.resp_body =~ "foo &amp; bar"
      assert conn.resp_body =~ "build &lt; test"
    end

    test "includes webUrl for each project", %{conn: conn} do
      pipeline = insert_pipeline("web-url-pipe", "group1")
      insert_stage_config(pipeline.id, "stage1")
      pi = insert_pipeline_instance(pipeline.id, 42, "42")
      insert_stage_instance(pi.id, "stage1", 1, "Completed", "Passed")

      conn = get(conn, "/go/cctray.xml")

      assert conn.resp_body =~ ~s(webUrl="/go/pipelines/web-url-pipe/42/stage1/1")
    end
  end

  # ── helpers ──

  defp insert_pipeline(name, group) do
    Repo.insert!(%Pipeline{
      name: name,
      group: group,
      label_template: "${COUNT}"
    })
  end

  defp insert_stage_config(pipeline_id, name) do
    Repo.insert!(%Stage{
      name: name,
      pipeline_id: pipeline_id,
      approval_type: "success"
    })
  end

  defp insert_pipeline_instance(pipeline_id, counter, label) do
    Repo.insert!(%PipelineInstance{
      pipeline_id: pipeline_id,
      counter: counter,
      label: label,
      natural_order: counter * 1.0,
      build_cause: %{"triggerMessage" => "test trigger"}
    })
  end

  defp insert_stage_instance(pipeline_instance_id, name, counter, state, result) do
    now = DateTime.utc_now()
    Repo.insert!(%StageInstance{
      pipeline_instance_id: pipeline_instance_id,
      name: name,
      counter: counter,
      order_id: 1,
      state: state,
      result: result,
      approval_type: "success",
      created_time: now,
      completed_at: NaiveDateTime.truncate(now, :second),
      latest_run: true,
      artifacts_deleted: false
    })
  end
end
