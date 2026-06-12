defmodule ExGoCD.AccountsTest do
  use ExGoCD.DataCase

  alias ExGoCD.Accounts
  alias ExGoCD.Accounts.User

  describe "user schema and changesets" do
    @valid_attrs %{
      username: "john_doe",
      display_name: "John Doe",
      roles: ["admin", "developer"],
      status: "Active"
    }

    test "changeset with valid attributes is valid" do
      changeset = User.changeset(%User{}, @valid_attrs)
      assert changeset.valid?
    end

    test "changeset requires username and display_name" do
      changeset = User.changeset(%User{}, %{})
      refute changeset.valid?
      assert %{username: ["can't be blank"], display_name: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset validates status values" do
      changeset = User.changeset(%User{}, Map.put(@valid_attrs, :status, "Invalid"))
      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "has_role?/2 supports both atom and string role queries" do
      user = %User{roles: ["admin", "developer"]}

      assert User.has_role?(user, :admin)
      assert User.has_role?(user, "admin")
      assert User.has_role?(user, :developer)
      assert User.has_role?(user, "developer")

      refute User.has_role?(user, :viewer)
      refute User.has_role?(user, "viewer")
    end
  end

  describe "accounts CRUD" do
    test "list_users/0 lists all users ordered by username" do
      assert Accounts.list_users() == []

      {:ok, user2} = Accounts.create_user(%{username: "bob", display_name: "Bob"})
      {:ok, user1} = Accounts.create_user(%{username: "alice", display_name: "Alice"})

      assert Accounts.list_users() == [user1, user2]
    end

    test "get_user!/1 returns the user with the given id" do
      {:ok, user} = Accounts.create_user(%{username: "alice", display_name: "Alice"})
      assert Accounts.get_user!(user.id) == user
    end

    test "get_user_by_username/1 gets user" do
      {:ok, user} = Accounts.create_user(%{username: "alice", display_name: "Alice"})
      assert Accounts.get_user_by_username("alice") == user
      assert Accounts.get_user_by_username("bob") == nil
    end

    test "create_user/1 with valid attributes creates a user" do
      assert {:ok, %User{} = user} = Accounts.create_user(%{username: "alice", display_name: "Alice"})
      assert user.username == "alice"
      assert user.display_name == "Alice"
      assert user.roles == []
      assert user.status == "Active"
    end

    test "create_user/1 enforces username uniqueness constraint" do
      {:ok, _} = Accounts.create_user(%{username: "alice", display_name: "Alice"})
      assert {:error, changeset} = Accounts.create_user(%{username: "alice", display_name: "Alice 2"})
      assert %{username: ["has already been taken"]} = errors_on(changeset)
    end

    test "update_user/2 updates fields" do
      {:ok, user} = Accounts.create_user(%{username: "alice", display_name: "Alice"})
      assert {:ok, updated} = Accounts.update_user(user, %{display_name: "Alice Cooper", roles: ["admin"]})
      assert updated.display_name == "Alice Cooper"
      assert updated.roles == ["admin"]
    end

    test "delete_user/1 deletes the user" do
      {:ok, user} = Accounts.create_user(%{username: "alice", display_name: "Alice"})
      assert {:ok, _} = Accounts.delete_user(user)
      assert Accounts.get_user_by_username("alice") == nil
    end
  end

  describe "get_current_user/1 session loading & edge bootstrapping" do
    test "unauthenticated empty DB returns default admin guest user" do
      user = Accounts.get_current_user(%{})
      assert user.username == "guest"
      assert User.has_role?(user, :admin)
    end

    test "unauthenticated non-empty DB returns default viewer guest user" do
      {:ok, _} = Accounts.create_user(%{username: "admin", display_name: "Admin"})
      user = Accounts.get_current_user(%{})
      assert user.username == "guest"
      refute User.has_role?(user, :admin)
    end

    test "session matches existing active user in DB" do
      {:ok, db_user} = Accounts.create_user(%{username: "alice", display_name: "Alice", roles: ["developer"]})
      user = Accounts.get_current_user(%{"username" => "alice"})
      assert user.id == db_user.id
      assert user.username == "alice"
      assert User.has_role?(user, :developer)
    end

    test "session matches existing disabled user in DB clears all active roles" do
      {:ok, db_user} = Accounts.create_user(%{username: "alice", display_name: "Alice", roles: ["developer"], status: "Disabled"})
      user = Accounts.get_current_user(%{"username" => "alice"})
      assert user.id == db_user.id
      refute User.has_role?(user, :developer)
      assert user.roles == []
    end
  end
end
