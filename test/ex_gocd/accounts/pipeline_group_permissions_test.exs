defmodule ExGoCD.Accounts.PipelineGroupPermissionsTest do
  @moduledoc """
  Tests for pipeline group permissions — granular RBAC on pipeline groups.
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.User

  setup do
    # Create a non-admin test user
    {:ok, user} = Accounts.create_user(%{
      username: "rbac_test_#{System.unique_integer([:positive])}",
      display_name: "RBAC Test User",
      roles: [],
      status: "Active"
    })
    {:ok, user: user}
  end

  describe "grant_pipeline_group_permission/3" do
    test "grants viewer role on a pipeline group", %{user: user} do
      assert {:ok, perm} = Accounts.grant_pipeline_group_permission(user.id, "my-group", "viewer")
      assert perm.role == "viewer"
      assert perm.pipeline_group == "my-group"
    end

    test "grants operator role on a pipeline group", %{user: user} do
      assert {:ok, perm} = Accounts.grant_pipeline_group_permission(user.id, "prod", "operator")
      assert perm.role == "operator"
    end

    test "grants admin role on a pipeline group", %{user: user} do
      assert {:ok, perm} = Accounts.grant_pipeline_group_permission(user.id, "prod", "admin")
      assert perm.role == "admin"
    end

    test "updates existing permission on conflict", %{user: user} do
      {:ok, _} = Accounts.grant_pipeline_group_permission(user.id, "shared", "viewer")
      {:ok, _} = Accounts.grant_pipeline_group_permission(user.id, "shared", "operator")

      perms = Accounts.list_pipeline_group_permissions(user.id)
      assert length(perms) == 1
      assert hd(perms).role == "operator"
    end

    test "rejects invalid role", %{user: user} do
      assert {:error, changeset} = Accounts.grant_pipeline_group_permission(user.id, "g", "superadmin")
      assert "is invalid" in errors_on(changeset).role
    end
  end

  describe "revoke_pipeline_group_permission/2" do
    test "removes an existing permission", %{user: user} do
      {:ok, _} = Accounts.grant_pipeline_group_permission(user.id, "g", "viewer")
      assert {:ok, _} = Accounts.revoke_pipeline_group_permission(user.id, "g")
      assert Accounts.list_pipeline_group_permissions(user.id) == []
    end

    test "returns error for nonexistent permission", %{user: user} do
      assert {:error, :not_found} = Accounts.revoke_pipeline_group_permission(user.id, "nonexistent")
    end
  end

  describe "can_access_pipeline_group?/3" do
    test "global admin can access any group" do
      {:ok, admin} = Accounts.create_user(%{
        username: "global_admin_#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })
      assert Accounts.can_access_pipeline_group?(admin, "any-group", "admin")
      assert Accounts.can_access_pipeline_group?(admin, "any-group", "operator")
      assert Accounts.can_access_pipeline_group?(admin, "any-group", "viewer")
    end

    test "group admin can access with any required role", %{user: user} do
      {:ok, _} = Accounts.grant_pipeline_group_permission(user.id, "team-a", "admin")
      assert Accounts.can_access_pipeline_group?(user, "team-a", "admin")
      assert Accounts.can_access_pipeline_group?(user, "team-a", "operator")
      assert Accounts.can_access_pipeline_group?(user, "team-a", "viewer")
    end

    test "group operator cannot meet admin requirement", %{user: user} do
      {:ok, _} = Accounts.grant_pipeline_group_permission(user.id, "team-b", "operator")
      refute Accounts.can_access_pipeline_group?(user, "team-b", "admin")
      assert Accounts.can_access_pipeline_group?(user, "team-b", "operator")
      assert Accounts.can_access_pipeline_group?(user, "team-b", "viewer")
    end

    test "viewer can only meet viewer requirement", %{user: user} do
      {:ok, _} = Accounts.grant_pipeline_group_permission(user.id, "team-c", "viewer")
      refute Accounts.can_access_pipeline_group?(user, "team-c", "admin")
      refute Accounts.can_access_pipeline_group?(user, "team-c", "operator")
      assert Accounts.can_access_pipeline_group?(user, "team-c", "viewer")
    end

    test "user without permission cannot access", %{user: user} do
      refute Accounts.can_access_pipeline_group?(user, "restricted", "viewer")
    end

    test "guest (nil id) with no roles cannot access" do
      guest = %User{id: nil, username: "guest", display_name: "Guest", roles: [], status: "Active"}
      refute Accounts.can_access_pipeline_group?(guest, "any-group", "viewer")
    end
  end
end
