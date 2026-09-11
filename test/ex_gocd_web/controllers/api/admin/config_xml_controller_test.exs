defmodule ExGoCDWeb.API.Admin.ConfigXmlControllerTest do
  use ExGoCDWeb.ConnCase

  test "returns the cruise-config XML", %{conn: conn} do
    conn = get(conn, "/api/admin/config.xml")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "application/xml"
    assert conn.resp_body =~ "<cruise"
  end
end
