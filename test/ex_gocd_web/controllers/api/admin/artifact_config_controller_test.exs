defmodule ExGoCDWeb.API.Admin.ArtifactConfigControllerTest do
  use ExGoCDWeb.ConnCase

  @path "/api/admin/config/server/artifact_config"

  test "reports the directory, the purge settings and the ETag a write has to carry",
       %{conn: conn} do
    conn = get(conn, @path)

    assert %{
             "artifacts_dir" => "artifacts",
             "purge_settings" => %{
               "purge_start_disk_space" => 10.0,
               "purge_upto_disk_space" => 20.0
             }
           } = json_response(conn, 200)

    assert [etag] = get_resp_header(conn, "etag")
    assert etag =~ ~r/^"[0-9a-f]{64}"$/
  end

  describe "the documented write" do
    test "stores the directory and the purge settings", %{conn: conn} do
      conn =
        update(conn, %{
          artifacts_dir: "/data/artifacts",
          purge_settings: %{purge_start_disk_space: 30, purge_upto_disk_space: 60}
        })

      assert %{
               "artifacts_dir" => "/data/artifacts",
               "purge_settings" => %{
                 "purge_start_disk_space" => 30.0,
                 "purge_upto_disk_space" => 60.0
               }
             } = json_response(conn, 200)
    end

    test "answers at the path api.go.cd documents", %{conn: conn} do
      conn =
        put_json(
          conn,
          "/go/api/admin/config/server/artifact_config",
          %{
            artifacts_dir: "/data/documented"
          },
          etag(conn)
        )

      assert %{"artifacts_dir" => "/data/documented"} = json_response(conn, 200)

      assert %{"artifacts_dir" => "/data/documented"} =
               json_response(
                 get(build_conn(), "/go/api/admin/config/server/artifact_config"),
                 200
               )
    end

    test "refuses a write that carries no If-Match", %{conn: conn} do
      conn = put_json(conn, @path, %{artifacts_dir: "/data/anywhere"})

      assert %{"message" => message} = json_response(conn, 412)
      assert message =~ "Someone has modified the entity"
    end

    test "refuses a write whose If-Match no longer matches", %{conn: conn} do
      conn = put_json(conn, @path, %{artifacts_dir: "/data/anywhere"}, ~s("stale"))

      assert json_response(conn, 412)
    end

    test "refuses purge settings that do not add up, and keeps the directory", %{conn: conn} do
      conn = update(conn, %{purge_settings: %{purge_upto_disk_space: 60}})

      assert %{"errors" => %{"purge_start_disk_space" => [message]}} =
               json_response(conn, 422)

      assert message =~ "trigger value has to be specified"

      assert %{"artifacts_dir" => "artifacts"} =
               json_response(get(build_conn(), @path), 200)
    end
  end

  defp update(conn, body), do: put_json(conn, @path, body, etag(conn))

  defp put_json(conn, path, body, etag \\ nil) do
    conn =
      conn
      |> put_req_header("content-type", "application/json")

    conn =
      if etag do
        put_req_header(conn, "if-match", etag)
      else
        conn
      end

    put(conn, path, Jason.encode!(body))
  end

  defp etag(conn) do
    conn
    |> get(@path)
    |> get_resp_header("etag")
    |> List.first()
  end
end
