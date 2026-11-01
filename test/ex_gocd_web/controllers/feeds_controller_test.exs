defmodule ExGoCDWeb.FeedsControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  import ExGoCD.PipelinesFixtures,
    only: [insert_pipeline: 2, insert_pipeline_instance: 2, insert_stage_instance: 3]

  describe "GET /api/feeds/pipelines.xml" do
    test "is an Atom feed with no entries when nothing has run", %{conn: conn} do
      conn = get(conn, "/api/feeds/pipelines.xml")

      assert conn.status == 200
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "atom+xml"
      assert conn.resp_body =~ ~s(<feed xmlns="http://www.w3.org/2005/Atom">)
      assert conn.resp_body =~ "<title>ex_gocd Pipeline Feed</title>"
      refute conn.resp_body =~ "<entry>"
    end

    test "names the pipeline and the counter of a run", %{conn: conn} do
      pipeline = insert_pipeline("deploy", group: "test")
      insert_pipeline_instance(pipeline.id, 5)

      body =
        conn
        |> get("/api/feeds/pipelines.xml")
        |> response(200)

      assert body =~ "deploy #5 5"
      assert body =~ "urn:exgocd:pipeline:deploy:5"
    end
  end

  describe "GET /api/feeds/pipelines/:pipeline_name/stages.xml" do
    test "gives each stage entry exactly one title", %{conn: conn} do
      pipeline = insert_pipeline("deploy", group: "test")
      instance = insert_pipeline_instance(pipeline.id, 5)

      insert_stage_instance(instance.id, "build",
        counter: 1,
        state: "Completed",
        result: "Passed"
      )

      body =
        conn
        |> get("/api/feeds/pipelines/deploy/stages.xml")
        |> response(200)

      assert body =~ "deploy #5 build Completed"

      assert [entry] = Regex.run(~r{<entry>.*?</entry>}s, body)
      assert title_count(entry) == 1
    end
  end

  defp title_count(entry), do: length(String.split(entry, "<title>")) - 1
end
