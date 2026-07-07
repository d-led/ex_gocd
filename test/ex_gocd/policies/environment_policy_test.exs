defmodule ExGoCD.Policies.EnvironmentPolicyTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Accounts.Role
  alias ExGoCD.Accounts.User
  alias ExGoCD.Policies.EnvironmentPolicy
  alias ExGoCD.Repo

  # ═══════════════════════════════════════════════════════════════════════
  # GoCD parity: per-environment RBAC via role policies
  # ═══════════════════════════════════════════════════════════════════════
  describe "per-environment RBAC" do
    setup do
      Repo.delete_all(Role)
      Repo.delete_all(User)

      admin =
        Repo.insert!(%User{
          username: "admin",
          display_name: "Admin",
          roles: ["admin"],
          status: "Active"
        })

      env_admin =
        Repo.insert!(%User{
          username: "env-admin",
          display_name: "Env Admin",
          roles: ["env-admin"],
          status: "Active"
        })

      viewer =
        Repo.insert!(%User{
          username: "viewer",
          display_name: "Viewer",
          roles: ["viewer"],
          status: "Active"
        })

      Repo.insert!(%Role{
        name: "env-admin",
        type: "gocd",
        users: ["env-admin"],
        policy: %{
          "allow" => [
            %{"action" => "view", "type" => "environment", "resource" => "QA"},
            %{"action" => "view", "type" => "environment", "resource" => "UAT"},
            %{"action" => "administer", "type" => "environment", "resource" => "QA"}
          ]
        }
      })

      {:ok, admin: admin, env_admin: env_admin, viewer: viewer}
    end

    test "admin always has access regardless of policy", %{admin: admin} do
      assert EnvironmentPolicy.has_permission?(admin, "view", "environment", "any-env")
      assert EnvironmentPolicy.has_permission?(admin, "administer", "environment", "any-env")
    end

    test "role-policy user can view only allowed environments", %{env_admin: env_admin} do
      assert EnvironmentPolicy.has_permission?(env_admin, "view", "environment", "QA")
      assert EnvironmentPolicy.has_permission?(env_admin, "view", "environment", "UAT")
      refute EnvironmentPolicy.has_permission?(env_admin, "view", "environment", "Prod")
      refute EnvironmentPolicy.has_permission?(env_admin, "view", "environment", "Staging")
    end

    test "role-policy user can administer only allowed environments", %{env_admin: env_admin} do
      assert EnvironmentPolicy.has_permission?(env_admin, "administer", "environment", "QA")
      refute EnvironmentPolicy.has_permission?(env_admin, "administer", "environment", "UAT")
    end

    test "viewer without policy has no per-environment access", %{viewer: viewer} do
      refute EnvironmentPolicy.has_permission?(viewer, "view", "environment", "QA")
      refute EnvironmentPolicy.has_permission?(viewer, "administer", "environment", "QA")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # GoCD parity: wildcard resource matching
  # ═══════════════════════════════════════════════════════════════════════
  describe "wildcard policies" do
    setup do
      Repo.delete_all(Role)
      Repo.delete_all(User)

      Repo.insert!(%User{
        username: "admin",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

      global_viewer =
        Repo.insert!(%User{
          username: "global-viewer",
          display_name: "G",
          roles: ["global-viewer"],
          status: "Active"
        })

      Repo.insert!(%Role{
        name: "global-viewer",
        type: "gocd",
        users: ["global-viewer"],
        policy: %{
          "allow" => [
            %{"action" => "view", "type" => "environment", "resource" => "*"}
          ]
        }
      })

      {:ok, global_viewer: global_viewer}
    end

    test "wildcard * matches any environment for view", %{global_viewer: gv} do
      assert EnvironmentPolicy.has_permission?(gv, "view", "environment", "QA")
      assert EnvironmentPolicy.has_permission?(gv, "view", "environment", "UAT")
      assert EnvironmentPolicy.has_permission?(gv, "view", "environment", "any-env")
    end

    test "wildcard view does not grant administer", %{global_viewer: gv} do
      refute EnvironmentPolicy.has_permission?(gv, "administer", "environment", "QA")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # GoCD parity: global actions (used by controllers)
  # ═══════════════════════════════════════════════════════════════════════
  describe "global actions (view_environments, manage_environments, trigger_pipeline)" do
    setup do
      Repo.delete_all(Role)
      Repo.delete_all(User)

      admin =
        Repo.insert!(%User{
          username: "admin",
          display_name: "Admin",
          roles: ["admin"],
          status: "Active"
        })

      dev =
        Repo.insert!(%User{
          username: "dev",
          display_name: "Dev",
          roles: ["developer"],
          status: "Active"
        })

      viewer =
        Repo.insert!(%User{
          username: "viewer",
          display_name: "Viewer",
          roles: ["viewer"],
          status: "Active"
        })

      {:ok, admin: admin, dev: dev, viewer: viewer}
    end

    test "admin has full access", %{admin: admin} do
      assert :ok = EnvironmentPolicy.authorize(:manage_environments, admin, %{})
      assert :ok = EnvironmentPolicy.authorize(:view_environments, admin, %{})
      assert :ok = EnvironmentPolicy.authorize(:trigger_pipeline, admin, %{})
    end

    test "viewer can view environments globally but not manage", %{viewer: viewer, dev: dev} do
      assert :ok = EnvironmentPolicy.authorize(:view_environments, viewer, %{})
      assert {:error, :forbidden} = EnvironmentPolicy.authorize(:manage_environments, viewer, %{})
    end

    test "guest (no roles) cannot view environments", %{admin: _admin} do
      guest =
        Repo.insert!(%User{username: "guest", display_name: "Guest", roles: [], status: "Active"})

      assert {:error, :forbidden} = EnvironmentPolicy.authorize(:view_environments, guest, %{})
    end

    test "developer can trigger pipelines, viewer cannot", %{dev: dev, viewer: viewer} do
      assert :ok = EnvironmentPolicy.authorize(:trigger_pipeline, dev, %{})
      assert {:error, :forbidden} = EnvironmentPolicy.authorize(:trigger_pipeline, viewer, %{})
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # GoCD parity: Bodyguard integration (authorize returns booleans)
  # ═══════════════════════════════════════════════════════════════════════
  describe "Bodyguard integration" do
    setup do
      Repo.delete_all(Role)
      Repo.delete_all(User)

      admin =
        Repo.insert!(%User{
          username: "admin",
          display_name: "Admin",
          roles: ["admin"],
          status: "Active"
        })

      Repo.insert!(%User{
        username: "viewer",
        display_name: "Viewer",
        roles: ["viewer"],
        status: "Active"
      })

      {:ok, admin: admin}
    end

    test "authorize returns true/false for per-environment actions", %{admin: admin} do
      assert EnvironmentPolicy.authorize(:view_environment, admin, %{environment: "QA"})
    end

    test "authorize returns :ok/:error for global actions" do
      viewer = %User{username: "viewer", roles: ["viewer"], status: "Active"}
      assert :ok = EnvironmentPolicy.authorize(:view_environments, viewer, %{})
      assert {:error, :forbidden} = EnvironmentPolicy.authorize(:manage_environments, viewer, %{})
    end

    test "unknown actions return false" do
      admin = %User{username: "admin", roles: ["admin"], status: "Active"}
      refute EnvironmentPolicy.authorize(:unknown_action, admin, %{})
    end
  end
end
