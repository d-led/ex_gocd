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

  describe "the path api.go.cd documents" do
    setup do
      on_exit(fn ->
        System.delete_env("PHX_URL")
        System.delete_env("PHX_SECURE_URL")
        System.delete_env("SITE_URL")
      end)

      :ok
    end

    test "reports the URLs the server was started with", %{conn: conn} do
      System.put_env("PHX_URL", "http://foo.com")
      System.put_env("PHX_SECURE_URL", "https://foo.com")

      conn = get(conn, "/go/api/admin/config/server/site_urls")

      assert %{
               "site_url" => "http://foo.com",
               "secure_site_url" => "https://foo.com",
               "_links" => %{"self" => %{"href" => "/api/admin/config/server/site_urls"}}
             } = json_response(conn, 200)
    end

    test "falls back to the plain URL when only that one is set", %{conn: conn} do
      System.put_env("SITE_URL", "http://only.example")

      conn = get(conn, "/api/admin/config/server/site_urls")

      assert %{
               "site_url" => "http://only.example",
               "secure_site_url" => "http://only.example"
             } = json_response(conn, 200)
    end
  end
end
