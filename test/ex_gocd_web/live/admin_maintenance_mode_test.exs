defmodule ExGoCDWeb.AdminMaintenanceModeTest do
  @moduledoc """
  Maintenance mode is one flag for the whole server, not per test: while it is on,
  every trigger anywhere is refused. A test that flips it therefore cannot run
  beside other tests — this file is synchronous for that reason, and the rest of
  the admin page's tests stay parallel.
  """
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ExGoCD.Accounts
  alias ExGoCD.MaintenanceMode

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "maintenance-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    on_exit(fn -> MaintenanceMode.disable() end)

    %{conn: log_in_as(conn, admin.username)}
  end

  test "toggles maintenance mode on click", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    refute render(view) =~ "Enabled (Read-only)"

    view |> element("button", "Enable") |> render_click()

    assert render(view) =~ "Enabled (Read-only)"
    assert render(view) =~ "entered maintenance mode"

    view |> element("button", "Disable") |> render_click()

    refute render(view) =~ "Enabled (Read-only)"
    assert render(view) =~ "left maintenance mode"
  end
end
