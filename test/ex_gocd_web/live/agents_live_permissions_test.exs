defmodule ExGoCDWeb.AgentsLivePermissionsTest do
  @moduledoc """
  Enabling, disabling and deleting agents is an admin action. The page decides
  that once, in `is_user_admin`, and every handler reads it — so the behaviour to
  pin is that a signed-in viewer who presses the button changes nothing, and an
  admin who presses it changes the agent.
  """
  use ExGoCDWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ExGoCD.Accounts
  alias ExGoCD.Agents

  @agent_uuid "550e8400-e29b-41d4-a716-44665544000a"

  setup %{conn: conn} do
    {:ok, _} =
      Agents.register_agent(%{
        uuid: @agent_uuid,
        hostname: "gated-agent",
        ipaddress: "10.20.30.40"
      })

    {:ok, _} = Agents.disable_agent(@agent_uuid)

    %{conn: conn}
  end

  describe "a signed-in viewer" do
    setup %{conn: conn} do
      {:ok, viewer} =
        Accounts.create_user(%{
          username: "gated-viewer-#{System.unique_integer([:positive])}",
          display_name: "Viewer",
          roles: ["viewer"],
          status: "Active"
        })

      %{conn: log_in_as(conn, viewer.username)}
    end

    test "can open the agents page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/agents")

      assert html =~ "gated-agent"
      refute html =~ "CLEAN DISABLED"
    end

    test "cannot enable an agent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/agents")

      html = render_click(view, "enable", %{"uuid" => @agent_uuid})

      assert html =~ "not authorized"
      assert disabled?(@agent_uuid)
    end

    test "cannot delete an agent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/agents")

      html = render_click(view, "delete", %{"uuid" => @agent_uuid})

      assert html =~ "not authorized"
      refute Agents.get_agent_by_uuid(@agent_uuid) == nil
    end
  end

  describe "an admin" do
    setup %{conn: conn} do
      {:ok, admin} =
        Accounts.create_user(%{
          username: "gated-admin-#{System.unique_integer([:positive])}",
          display_name: "Admin",
          roles: ["admin"],
          status: "Active"
        })

      %{conn: log_in_as(conn, admin.username)}
    end

    test "enables an agent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/agents")

      html = render_click(view, "enable", %{"uuid" => @agent_uuid})

      assert html =~ "Agent enabled"
      refute disabled?(@agent_uuid)
    end
  end

  defp disabled?(uuid) do
    Agents.get_agent_by_uuid(uuid).disabled
  end
end
