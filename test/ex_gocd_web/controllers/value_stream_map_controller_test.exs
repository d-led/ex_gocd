defmodule ExGoCDWeb.ValueStreamMapControllerTest do
  use ExGoCDWeb.ConnCase

  test "GET /pipelines/value_stream_map/:pipeline_name/:pipeline_counter.json", %{conn: conn} do
    # When requesting JSON VSM for valid pipeline
    conn = get(conn, "/pipelines/value_stream_map/build-linux/1.json")

    # Then the response is 200 JSON with expected keys
    assert json_response(conn, 200) |> Map.get("current_pipeline") == "build-linux"
  end

  test "GET /materials/value_stream_map/:material_fingerprint/:revision.json", %{conn: conn} do
    # When requesting JSON VSM for valid material
    conn = get(conn, "/materials/value_stream_map/8d78bc9f6c661806/abcd1234ef.json")

    # Then the response is 200 JSON with expected keys
    assert json_response(conn, 200) |> Map.get("current_material") == "8d78bc9f6c661806"
  end

  test "GET /pipelines/value_stream_map/nonexistent/1.json returns 404", %{conn: conn} do
    # When requesting non-existent pipeline VSM
    conn = get(conn, "/pipelines/value_stream_map/nonexistent-pipeline/1.json")

    # Then the response is 404 JSON with error message
    assert json_response(conn, 404) |> Map.get("error") =~ "not found"
  end
end
