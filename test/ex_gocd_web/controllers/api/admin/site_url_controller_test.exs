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

  describe "the documented write" do
    test "POST stores the URLs links will use", %{conn: conn} do
      conn =
        post(conn, "/go/api/admin/config/server/site_urls", %{
          site_url: "http://ci.example",
          secure_site_url: "https://ci.example"
        })

      assert %{
               "site_url" => "http://ci.example",
               "secure_site_url" => "https://ci.example"
             } = json_response(conn, 200)

      assert %{"site_url" => "http://ci.example"} =
               json_response(
                 get(build_conn(), "/go/api/admin/config/server/site_urls"),
                 200
               )
    end

    test "PUT means the same as POST", %{conn: conn} do
      conn =
        put(conn, "/api/admin/config/server/site_urls", %{
          site_url: "http://put.example"
        })

      assert %{"site_url" => "http://put.example"} = json_response(conn, 200)
    end

    test "refuses a URL that does not start with http or https", %{conn: conn} do
      conn =
        post(conn, "/go/api/admin/config/server/site_urls", %{site_url: "ci.example"})

      assert %{"errors" => %{"site_url" => [message]}} = json_response(conn, 422)
      assert message =~ "must start with http/s"
    end
  end
end
