defmodule ExGoCDWeb.FeedsControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  import ExGoCD.PipelinesFixtures,
    only: [
      insert_material: 3,
      insert_modification: 2,
      insert_pipeline: 2,
      insert_pipeline_instance: 2,
      insert_pipeline_instance_by_name: 3,
      insert_pmr: 5,
      insert_stage_instance: 3
    ]

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

  describe "GET /api/feeds/materials/:pipeline/:counter/:fingerprint" do
    setup do
      pipeline = insert_pipeline("materials-feed", group: "test")
      instance = insert_pipeline_instance_by_name("materials-feed", 1, DateTime.utc_now())
      material = insert_material(pipeline, "git", "https://example.com/repo.git")
      modification = insert_modification(material, "abc123")
      insert_pmr(instance.id, material.id, modification.id, nil, "abc123")

      %{fingerprint: ExGoCD.Pipelines.material_fingerprint(material)}
    end

    test "names the revision the run was triggered with", %{conn: conn, fingerprint: fp} do
      body = conn |> get("/api/feeds/materials/materials-feed/1/#{fp}") |> response(200)

      assert body =~ "Revision abc123"
      assert [entry] = Regex.run(~r{<entry>.*?</entry>}s, body)
      assert title_count(entry) == 1
    end

    test "is empty for a material that run did not use", %{conn: conn} do
      body =
        conn
        |> get("/api/feeds/materials/materials-feed/1/0000000000000000")
        |> response(200)

      refute body =~ "<entry>"
    end

    test "answers a counter that is not a number as a bad request", %{conn: conn, fingerprint: fp} do
      conn = get(conn, "/api/feeds/materials/materials-feed/latest/#{fp}")

      assert conn.status == 400
    end
  end
end
