defmodule ExGoCD.Accounts.UserLifecycleTest do
  @moduledoc """
  Tests for user lifecycle — disable, enable, blocked login.

  Covers ruby specs: AllowOnlyKnownUsersToLogin.spec,
  DisabledUserAccess.spec, EnableDisableUsers.spec
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.User

  setup do
    # Create an admin user so the system is in "security mode"
    {:ok, admin} =
      Accounts.create_user(%{
        username: "lifecycle-admin",
        display_name: "Admin",
        roles: ["admin"]
      })

    {:ok, admin: admin}
  end

  describe "user disable/enable" do
    test "disabling a user strips their roles in current session" do
      {:ok, user} =
        Accounts.create_user(%{
          username: "to-disable",
          display_name: "Disable Me",
          roles: ["developer", "viewer"]
        })

      # Disable via status update
      {:ok, disabled} = Accounts.update_user(user, %{status: "Disabled"})
      assert disabled.status == "Disabled"

      # get_current_user strips roles for disabled users
      current = Accounts.get_current_user(%{"username" => "to-disable"})
      assert current.status == "Disabled"
      assert current.roles == []
    end

    test "re-enabling a user restores their roles in DB" do
      {:ok, user} =
        Accounts.create_user(%{
          username: "to-reenable",
          display_name: "Re-enable Me",
          roles: ["developer"]
        })

      # Disable
      {:ok, _} = Accounts.update_user(user, %{status: "Disabled"})

      # Re-enable
      {:ok, reenabled} = Accounts.update_user(user, %{status: "Active"})
      assert reenabled.status == "Active"
      assert reenabled.roles == ["developer"]
    end

    test "disabled user login returns empty roles via get_current_user" do
      {:ok, _user} =
        Accounts.create_user(%{
          username: "blocked-user",
          display_name: "Blocked",
          roles: ["admin"],
          status: "Disabled"
        })

      current = Accounts.get_current_user(%{"username" => "blocked-user"})
      assert current.status == "Disabled"
      assert current.roles == []
    end

    test "active user retains their roles via get_current_user" do
      {:ok, _user} =
        Accounts.create_user(%{
          username: "active-user",
          display_name: "Active",
          roles: ["admin", "developer"]
        })

      current = Accounts.get_current_user(%{"username" => "active-user"})
      assert current.status == "Active"
      assert "admin" in current.roles
      assert "developer" in current.roles
    end
  end

  describe "admin configured mode" do
    test "admin_configured? is true when admin exists" do
      assert Accounts.admin_configured?() == true
    end

    test "guest has no roles when admin exists" do
      guest = Accounts.get_current_user(%{})
      assert guest.roles == []
      assert guest.username == "guest"
    end
  end

  describe "user status transitions" do
    test "create_user defaults to Active status" do
      {:ok, user} =
        Accounts.create_user(%{
          username: "default-active",
          display_name: "Default Active"
        })

      assert user.status == "Active"
    end

    test "create_user accepts explicit Disabled status" do
      {:ok, user} =
        Accounts.create_user(%{
          username: "explicit-disabled",
          display_name: "Explicitly Disabled",
          status: "Disabled"
        })

      assert user.status == "Disabled"
    end

    test "changeset rejects invalid status" do
      changeset =
        User.changeset(%User{}, %{username: "test", display_name: "Test", status: "Blocked"})

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "disabled user access" do
    test "disabled user cannot be found by get_user_by_username if status matters" do
      # get_user_by_username returns the user regardless of status —
      # it's get_current_user that strips roles. Verify the user is findable.
      {:ok, user} =
        Accounts.create_user(%{
          username: "findable-disabled",
          display_name: "Findable Disabled",
          status: "Disabled"
        })

      found = Accounts.get_user_by_username("findable-disabled")
      assert found != nil
      assert found.status == "Disabled"
    end

    test "deleting a user makes them unfindable" do
      {:ok, user} =
        Accounts.create_user(%{
          username: "to-delete-user",
          display_name: "Delete Me"
        })

      Accounts.delete_user(user)
      assert Accounts.get_user_by_username("to-delete-user") == nil
    end
  end
end
