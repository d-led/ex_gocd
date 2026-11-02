defmodule ExGoCDWeb.API.Admin.BackupConfigControllerTest do
  @moduledoc """
  The backup settings are read and written at `/go/api/config/backup`, which is
  where api.go.cd documents them; ex_gocd served them only under
  `/go/api/admin/config/backup`, so a client following the documentation got a
  404.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCD.BackupConfig
  alias ExGoCD.Repo

  @path "/go/api/config/backup"

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "backup-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    %{conn: log_in_as(conn, admin.username)}
  end

  describe "a server nobody has configured yet" do
    test "has a backup config with the defaults", %{conn: conn} do
      body = conn |> get(@path) |> json_response(200)

      assert body["retention_days"] == 7
      assert body["enabled"] == true
      assert body["schedule"] == nil
    end
  end

  describe "POST followed by GET" do
    test "keeps what was written", %{conn: conn} do
      conn
      |> post(@path, %{"schedule" => "0 2 * * *", "backup_dir" => "/var/backups"})
      |> json_response(201)

      body = conn |> get(@path) |> json_response(200)

      assert body["schedule"] == "0 2 * * *"
      assert body["backup_dir"] == "/var/backups"
    end

    test "replaces the settings rather than adding a second config", %{conn: conn} do
      conn |> post(@path, %{"schedule" => "0 2 * * *"}) |> json_response(201)
      conn |> post(@path, %{"schedule" => "0 4 * * *"}) |> json_response(201)

      assert Repo.aggregate(BackupConfig, :count) == 1
      assert json_response(get(conn, @path), 200)["schedule"] == "0 4 * * *"
    end

    test "refuses a retention that keeps nothing", %{conn: conn} do
      body = conn |> post(@path, %{"retention_days" => 0}) |> json_response(422)

      assert body["errors"]["retention_days"] == ["must be greater than 0"]
    end
  end

  describe "DELETE" do
    test "removes the settings that were there", %{conn: conn} do
      conn |> post(@path, %{"schedule" => "0 2 * * *"}) |> json_response(201)

      conn |> delete(@path) |> json_response(200)

      assert Repo.aggregate(BackupConfig, :count) == 0
    end

    test "answers that nothing is there when nothing is", %{conn: conn} do
      conn = delete(conn, @path)

      assert json_response(conn, 404) == %{"error" => "No backup config"}
    end
  end
end
