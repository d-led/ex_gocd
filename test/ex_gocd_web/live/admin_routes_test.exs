defmodule ExGoCDWeb.AdminRoutesTest do
  @moduledoc """
  `/admin/:tab` is a catch-all, so any one-segment admin page has to be declared
  before it. Two were declared after it and could never be reached: the plugin
  dashboard, and an audit log page that AdminLive also renders as a tab.
  """
  use ExGoCDWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "/admin/plugins shows the plugin dashboard", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins")

    assert has_element?(view, "#plugin-status")
    assert has_element?(view, "#plugin-name")
  end

  test "/admin/audit_log shows the audit log", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/audit_log")

    assert has_element?(view, ~s(form[phx-change="search_audit_log"]))
  end
end
