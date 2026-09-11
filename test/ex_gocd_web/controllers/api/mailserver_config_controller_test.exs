defmodule ExGoCDWeb.API.MailserverConfigControllerTest do
  use ExGoCDWeb.ConnCase

  test "returns the mail server configuration", %{conn: conn} do
    conn = get(conn, "/api/config/mailserver")

    body = json_response(conn, 200)
    assert body["hostname"] == "localhost"
    assert body["port"] == 25
    assert body["username"] == ""
    assert body["encrypted_password"] == ""
    assert body["tls"] == false
    assert body["sender_email"] == "noreply@exgocd.local"
    assert body["admin_email"] == "noreply@exgocd.local"
  end
end
