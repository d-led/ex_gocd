defmodule ExGoCDWeb.API.Admin.SiteURLControllerTest do
  use ExGoCDWeb.ConnCase

  test "returns site URL configuration", %{conn: conn} do
    conn = get(conn, "/api/admin/site_url")
    assert conn.status == 200
    assert %{"site_url" => url} = json_response(conn, 200)
    assert String.starts_with?(url, "http://")
  end

  test "serves the same config under the /go/api/admin prefix", %{conn: conn} do
    conn = get(conn, "/go/api/admin/site_url")
    assert conn.status == 200
    assert %{"site_url" => url} = json_response(conn, 200)
    assert String.starts_with?(url, "http://")
  end

  test "serves admin resources under the /go/api/admin prefix", %{conn: conn} do
    conn = get(conn, "/go/api/admin/pipelines")
    assert conn.status == 200
  end
end
