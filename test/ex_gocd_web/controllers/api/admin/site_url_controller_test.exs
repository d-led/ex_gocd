defmodule ExGoCDWeb.API.Admin.SiteURLControllerTest do
  use ExGoCDWeb.ConnCase

  test "returns site URL configuration", %{conn: conn} do
    conn = get(conn, "/api/admin/site_url")
    assert conn.status == 200
    assert %{"site_url" => url} = json_response(conn, 200)
    assert String.starts_with?(url, "http://")
  end
end
