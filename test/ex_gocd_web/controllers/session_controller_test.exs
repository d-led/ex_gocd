defmodule ExGoCDWeb.SessionControllerTest do
  @moduledoc """
  The login page is the first page anybody sees, and it was the page nothing
  rendered: it picks a user from the list this server knows, and a page that
  cannot read that list is a 500 in front of the door.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts

  test "offers the users this server knows", %{conn: conn} do
    {:ok, _user} =
      Accounts.create_user(%{
        username: "login-page-user",
        display_name: "Login Page",
        roles: ["admin"],
        status: "Active"
      })

    body = conn |> get(~p"/auth/login") |> html_response(200)

    assert body =~ "Sign In"
    assert body =~ "login-page-user"
    assert body =~ ~s(name="session[username]")
  end

  test "carries where the person was going", %{conn: conn} do
    body = conn |> get(~p"/auth/login?return_to=/go/admin/config_xml") |> html_response(200)

    assert body =~ ~s(value="/go/admin/config_xml")
  end
end
