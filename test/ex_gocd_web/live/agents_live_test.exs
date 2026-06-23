defmodule ExGoCDWeb.AgentsLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias ExGoCD.Agents
  alias ExGoCD.Accounts

  @valid_uuid "550e8400-e29b-41d4-a716-446655440000"

  # Helper: creates a session map that get_current_user/1 will recognize as admin.
  defp admin_session do
    # Create a real admin user in DB so get_current_user finds it
    {:ok, user} =
      Accounts.create_user(%{
        username: "agents-test-admin",
        display_name: "Test Admin",
        password: "test123456",
        roles: ["admin"]
      })

    %{"username" => user.username}
  end

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
      {:ok, _registered} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "test-agent",
          ipaddress: "127.0.0.1"
        })

      {:ok, _view, html} = live(conn, ~p"/agents")

      assert html =~ "Total"
      assert html =~ "test-agent"
    end
  end

  describe "Schedule test job" do
    setup do
      {:ok, _} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "test-agent",
          ipaddress: "127.0.0.1"
        })

      {:ok, agent_uuid: @valid_uuid}
    end

    test "schedule test job button exists", %{conn: conn} do
      # Set session with admin user so the schedule button is visible
      session = admin_session()
      conn = Plug.Test.init_test_session(conn, session)

      {:ok, view, _html} = live(conn, ~p"/agents")

      # Click the schedule test job button
      html = view |> element("button", "SCHEDULE TEST JOB") |> render_click()

      # Should show a flash message about scheduling
      assert html =~ "scheduled"
    end
  end

  describe "clean disabled agents" do
    setup do
      {:ok, _} =
        Agents.register_agent(%{
          uuid: @valid_uuid,
          hostname: "disabled-agent",
          ipaddress: "10.0.0.1"
        })

      # Disable it
      Agents.disable_agent(@valid_uuid)

      {:ok, agent_uuid: @valid_uuid}
    end

    test "cleans disabled agents and shows count in flash", %{conn: conn} do
      session = admin_session()
      conn = Plug.Test.init_test_session(conn, session)

      {:ok, view, _html} = live(conn, ~p"/agents")

      # Verify the disabled agent appears
      assert render(view) =~ "disabled-agent"

      # Click CLEAN DISABLED
      html = view |> element("button", "CLEAN DISABLED") |> render_click()

      # Flash should show deletion count
      assert html =~ ~r{Deleted \d+ disabled agent}

      # The disabled agent should be gone from the table
      refute html =~ "disabled-agent"
    end

    test "non-admin cannot clean disabled agents", %{conn: conn} do
      # Create an admin user so admin_configured?() returns true,
      # making default_user() a non-admin guest (GoCD open-mode behavior).
      admin_session()

      conn = Plug.Test.init_test_session(conn, %{})

      {:ok, view, _html} = live(conn, ~p"/agents")

      # Non-admin shouldn't see the CLEAN DISABLED button
      refute render(view) =~ "CLEAN DISABLED"
    end
  end
end
