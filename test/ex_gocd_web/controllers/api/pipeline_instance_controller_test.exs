defmodule ExGoCDWeb.API.PipelineInstanceControllerTest do
  @moduledoc """
  The pipeline instance API: a pipeline's history, and one run of it by counter.
  The counter comes from the URL, so a value that is not a number has to be
  refused rather than raised.
  """
  use ExGoCDWeb.ConnCase, async: true

  import ExGoCD.PipelinesFixtures

  @pipeline "instance-api-pipeline"

  setup do
    insert_pipeline(@pipeline)
    instance = insert_pipeline_instance_by_name(@pipeline, 3, DateTime.utc_now())
    insert_stage_instance(instance.id, "build", state: "Passed", result: "Passed")

    :ok
  end

  describe "the history of a pipeline" do
    test "lists the run it has", %{conn: conn} do
      body = conn |> get("/api/pipelines/#{@pipeline}/history") |> json_response(200)

      assert [%{"counter" => 3}] = body["pipelines"]
      assert body["pagination"]["total"] == 1
    end

    test "says a pipeline it cannot find is missing", %{conn: conn} do
      body = conn |> get("/api/pipelines/no-such-pipeline/history") |> json_response(404)

      assert body["message"] =~ "not found"
    end
  end

  describe "one run of a pipeline" do
    test "describes the run and its stages", %{conn: conn} do
      body = conn |> get("/api/pipelines/#{@pipeline}/3") |> json_response(200)

      assert body["name"] == @pipeline
      assert body["counter"] == 3
      assert [%{"name" => "build"}] = body["stages"]
    end

    test "says a run it cannot find is missing", %{conn: conn} do
      body = conn |> get("/api/pipelines/#{@pipeline}/99") |> json_response(404)

      assert body["message"] =~ "not found"
    end

    test "answers a counter that is not a number as a bad request", %{conn: conn} do
      body = conn |> get("/api/pipelines/#{@pipeline}/latest") |> json_response(400)

      assert body["message"] =~ "whole number"
    end
  end
end
