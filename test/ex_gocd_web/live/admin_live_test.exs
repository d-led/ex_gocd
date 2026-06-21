defmodule ExGoCDWeb.AdminLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    alias ExGoCD.Pipelines.Pipeline
    alias ExGoCD.Repo

    # Clean sandbox insert
    Repo.insert!(%Pipeline{name: "build-linux", group: "defaultGroup", label_template: "${COUNT}"})
    Repo.insert!(%Pipeline{name: "deploy-staging", group: "defaultGroup", label_template: "${COUNT}"})
    Repo.insert!(%Pipeline{name: "deploy-production", group: "defaultGroup", label_template: "${COUNT}"})
    Repo.insert!(%Pipeline{name: "demo-app", group: "testGroup", label_template: "${COUNT}"})
    Repo.insert!(%Pipeline{name: "e2e-tests", group: "testGroup", label_template: "${COUNT}"})

    # Seed environments for the environments tab assertions
    {:ok, _} = ExGoCD.Environments.create_environment(%{"name" => "staging"})
    {:ok, _} = ExGoCD.Environments.create_environment(%{"name" => "production"})

    # Seed default users — GoCD security mode requires at least one admin to enforce RBAC
    {:ok, _} = ExGoCD.Accounts.create_user(%{username: "admin", display_name: "System Administrator", roles: ["admin", "developer"], status: "Active"})
    {:ok, _} = ExGoCD.Accounts.create_user(%{username: "developer", display_name: "Lead Developer", roles: ["developer"], status: "Active"})
    {:ok, _} = ExGoCD.Accounts.create_user(%{username: "viewer", display_name: "Guest Viewer", roles: [], status: "Active"})

    :ok
  end

  describe "Admin Dashboard Page" do
    setup %{conn: conn} do
      {:ok, conn: log_in_as(conn, "admin")}
    end

    test "mounts and displays default overview tab", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin")

      assert html =~ "Administration"
      assert html =~ "Server Status"
      assert html =~ "Operations Control"
      assert page_title(view) =~ "GoCD Administration - Overview"
    end

    test "navigates to different tabs via URLs", %{conn: conn} do
      # Pipelines tab
      {:ok, view, _html} = live(conn, ~p"/admin/pipelines")
      html = render(view)
      assert html =~ "Pipelines"
      assert html =~ "defaultGroup"
      assert html =~ "build-linux"
      assert page_title(view) =~ "GoCD Administration - Pipelines"

      # Environments tab
      {:ok, view, _html} = live(conn, ~p"/admin/environments")
      html = render(view)
      assert html =~ "Environments"
      assert html =~ "staging"
      assert html =~ "production"
      assert page_title(view) =~ "GoCD Administration - Environments"

      # Server config tab
      {:ok, view, _html} = live(conn, ~p"/admin/server")
      html = render(view)
      assert html =~ "Server Configuration"
      assert html =~ "Backup Configuration Database"
      assert page_title(view) =~ "GoCD Administration - Server"

      # Security tab
      {:ok, view, _html} = live(conn, ~p"/admin/security")
      html = render(view)
      assert html =~ "Security"
      assert html =~ "admin"
      assert html =~ "developer"
      assert page_title(view) =~ "GoCD Administration - Security"
    end

    test "toggles maintenance mode on click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      # Initially disabled
      refute render(view) =~ "Enabled (Read-only)"

      # Enable it
      view
      |> element("button", "Enable")
      |> render_click()

      assert render(view) =~ "Enabled (Read-only)"
      assert render(view) =~ "entered maintenance mode"

      # Disable it
      view
      |> element("button", "Disable")
      |> render_click()

      refute render(view) =~ "Enabled (Read-only)"
      assert render(view) =~ "left maintenance mode"
    end

    test "performs database configuration backup simulation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/server")

      # Initially backup status is Idle
      assert render(view) =~ "Idle"

      # Trigger backup
      view
      |> element("button", "Start Backup Now")
      |> render_click()

      assert render(view) =~ "Running Backup..."
      assert render(view) =~ "Config backup started at"

      # Complete backup via process message (simulating send_after timeout)
      send(view.pid, :backup_complete)

      # Ensure it completed successfully
      assert render(view) =~ "Completed"
      assert render(view) =~ "Backup saved to: /var/lib/go-server/db/backups/"
      assert render(view) =~ "completed successfully"
    end

    test "allows searching/filtering pipelines within groups", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/pipelines")

      assert render(view) =~ "build-linux"
      assert render(view) =~ "deploy-production"

      # Search for "linux"
      view
      |> form("form[phx-change='search_pipelines']", %{"query" => "linux"})
      |> render_change()

      assert render(view) =~ "build-linux"
      refute render(view) =~ "deploy-production"

      # Clear search
      view
      |> form("form[phx-change='search_pipelines']", %{"query" => ""})
      |> render_change()

      assert render(view) =~ "build-linux"
      assert render(view) =~ "deploy-production"
    end

    test "allows creating and deleting pipeline groups", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/pipelines")

      refute render(view) =~ "newMarketingGroup"

      # Open creation form modal
      view
      |> element("button", "Create new pipeline group")
      |> render_click()

      # Add new group
      view
      |> form("form[phx-submit='create_pipeline_group']", %{"name" => "newMarketingGroup"})
      |> render_submit()

      assert render(view) =~ "newMarketingGroup"
      assert render(view) =~ "created successfully"

      # Delete group
      view
      |> element("button[phx-value-name='newMarketingGroup']")
      |> render_click()

      assert render(view) =~ "was deleted"

      # Clear flash to remove it from success alert
      view
      |> element("button[phx-click='clear_flash']")
      |> render_click()

      refute render(view) =~ "newMarketingGroup"
    end

    test "maps GoCD compatibility sub-paths to unified admin tabs", %{conn: conn} do
      # /admin/users -> security tab
      {:ok, view, _html} = live(conn, ~p"/admin/users")
      assert render(view) =~ "Security"
      assert page_title(view) =~ "GoCD Administration - Security"

      # /admin/security/roles -> security tab
      {:ok, view, _html} = live(conn, ~p"/admin/security/roles")
      assert render(view) =~ "Security"

      # /admin/backup -> server tab
      {:ok, view, _html} = live(conn, ~p"/admin/backup")
      assert render(view) =~ "Server Configuration"
      assert page_title(view) =~ "GoCD Administration - Server"

      # /admin/config/server -> server tab
      {:ok, view, _html} = live(conn, ~p"/admin/config/server")
      assert render(view) =~ "Server Configuration"
    end

    test "manages users: creation, updates, toggles status, and deletion", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/security")

      # Initially seeded users are present
      assert render(view) =~ "admin"
      assert render(view) =~ "developer"
      assert render(view) =~ "viewer"

      # Open "Add User" modal
      view
      |> element("button", "Add User")
      |> render_click()

      # Submit add user form
      view
      |> form("form[phx-submit='save_user']", %{
        "username" => "johndoe",
        "display_name" => "John Doe",
        "roles" => ["developer", "viewer"]
      })
      |> render_submit()

      assert render(view) =~ "User created successfully"
      assert render(view) =~ "johndoe"
      assert render(view) =~ "John Doe"

      # Get the new user ID from DB
      johndoe = ExGoCD.Accounts.get_user_by_username("johndoe")

      # Open Manage Roles modal for johndoe
      view
      |> element("button[phx-click='open_edit_user_roles_modal'][phx-value-id='#{johndoe.id}']")
      |> render_click()

      # Modify display_name and roles
      view
      |> form("form[phx-submit='save_user']", %{
        "display_name" => "Johnathan Doe",
        "roles" => ["admin"]
      })
      |> render_submit()

      assert render(view) =~ "User configuration updated successfully"
      assert render(view) =~ "Johnathan Doe"
      refute render(view) =~ "John Doe"

      # Toggle user status (Disable johndoe)
      view
      |> element("button[phx-click='toggle_user_status'][phx-value-id='#{johndoe.id}']", "Disable")
      |> render_click()

      assert render(view) =~ "User status updated successfully"
      assert render(view) =~ "Disabled"

      # Enable johndoe back
      view
      |> element("button[phx-click='toggle_user_status'][phx-value-id='#{johndoe.id}']", "Enable")
      |> render_click()

      assert render(view) =~ "User status updated successfully"
      assert render(view) =~ "Active"

      # Delete johndoe
      view
      |> element("button[phx-click='delete_user'][phx-value-id='#{johndoe.id}']")
      |> render_click()

      assert render(view) =~ "User deleted successfully"
      refute render(view) =~ "Johnathan Doe"
    end
  end
end
