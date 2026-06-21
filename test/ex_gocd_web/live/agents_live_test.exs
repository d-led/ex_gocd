defmodule ExGoCDWeb.AgentsLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias ExGoCD.Agents

  @valid_uuid "550e8400-e29b-41d4-a716-446655440000"

  describe "Agents page rendering" do
    test "renders agents page with header", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/agents")

      assert html =~ "Agents"
      assert html =~ "Filter agents"
    end

    test "shows static/elastic tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/agents")

      assert html =~ "STATIC"
      assert html =~ "ELASTIC"
    end

    test "shows agent count summary", %{conn: conn} do
      {:ok, registered} = Agents.register_agent(%{
        uuid: @valid_uuid, hostname: "test-agent", ipaddress: "127.0.0.1"
      })

      {:ok, _view, html} = live(conn, ~p"/agents")

      assert html =~ "Total"
      assert html =~ "test-agent"
    end
  end

  describe "Schedule test job" do
    setup do
      {:ok, _} = Agents.register_agent(%{
        uuid: @valid_uuid, hostname: "test-agent", ipaddress: "127.0.0.1"
      })
      {:ok, agent_uuid: @valid_uuid}
    end

    test "schedule test job button exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/agents")

      # Click the schedule test job button
      html = view |> element("button", "Schedule Test Job") |> render_click()

      # Should show a flash message about scheduling
      assert html =~ "scheduled"
    end
  end
end
