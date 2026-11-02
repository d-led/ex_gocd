defmodule ExGoCDWeb.API.AuthorisationTest do
  @moduledoc """
  What a token is allowed to do beyond reading. Several routes here were declared
  under the `:api` pipeline, which authenticates a token and asks nothing else, so
  a member could do what GoCD reserves for an admin.

  Reading the agent list is for anyone authenticated; enabling, disabling,
  renaming, killing the work an agent runs and deleting it are admin acts, as in
  GoCD. Registering is what an agent does for itself, so that stays open — an
  agent registers with the token its launcher was given, not with a user's.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCD.Agents

  setup do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    {:ok, member} =
      Accounts.create_user(%{
        username: "member-#{System.unique_integer([:positive])}",
        display_name: "Member",
        roles: [],
        status: "Active"
      })

    {:ok, agent} =
      Agents.register_agent(%{
        uuid: Ecto.UUID.generate(),
        hostname: "auth-agent-#{System.unique_integer([:positive])}",
        ipaddress: "127.0.0.1"
      })

    %{admin: admin, member: member, agent: agent}
  end

  describe "as someone who is not an admin" do
    setup %{conn: conn, member: member} do
      conn = conn |> Plug.Test.init_test_session(%{}) |> log_in_as(member.username)
      %{conn: conn}
    end

    test "can read the agent list", %{conn: conn, agent: agent} do
      body = conn |> get("/go/api/agents") |> json_response(200)

      assert Enum.any?(body["_embedded"]["agents"], &(&1["uuid"] == agent.uuid))
    end

    test "cannot disable an agent", %{conn: conn, agent: agent} do
      assert json_response(put(conn, "/go/api/agents/#{agent.uuid}/disable"), :forbidden)
      assert agent |> reload() |> Map.fetch!(:disabled) == false
    end

    test "cannot enable an agent", %{conn: conn, agent: agent} do
      assert json_response(put(conn, "/go/api/agents/#{agent.uuid}/enable"), :forbidden)
    end

    test "cannot rename an agent", %{conn: conn, agent: agent} do
      body = %{"hostname" => "renamed-by-a-member"}

      assert json_response(patch(conn, "/go/api/agents/#{agent.uuid}", body), :forbidden)
      assert agent |> reload() |> Map.fetch!(:hostname) != "renamed-by-a-member"
    end

    test "cannot kill the work an agent runs", %{conn: conn, agent: agent} do
      assert json_response(
               post(conn, "/go/api/agents/#{agent.uuid}/kill_running_tasks"),
               :forbidden
             )
    end

    test "cannot delete an agent", %{conn: conn, agent: agent} do
      assert json_response(delete(conn, "/go/api/agents/#{agent.uuid}"), :forbidden)
      assert Agents.get_agent_by_uuid(agent.uuid)
    end

    test "cannot bulk delete agents", %{conn: conn, agent: agent} do
      body = %{"uuids" => [agent.uuid]}

      assert json_response(delete(conn, "/go/api/agents", body), :forbidden)
      assert Agents.get_agent_by_uuid(agent.uuid)
    end
  end

  describe "an agent registering itself" do
    test "is let through without admin rights", %{conn: conn} do
      uuid = Ecto.UUID.generate()

      conn =
        post(conn, "/go/api/agents/register", %{
          "uuid" => uuid,
          "hostname" => "self-registering",
          "ipaddress" => "127.0.0.1"
        })

      assert conn.status in [200, 201]
      assert Agents.get_agent_by_uuid(uuid)
    end
  end

  describe "as an admin" do
    setup %{conn: conn, admin: admin} do
      conn = conn |> Plug.Test.init_test_session(%{}) |> log_in_as(admin.username)
      %{conn: conn}
    end

    test "can disable an agent", %{conn: conn, agent: agent} do
      assert conn |> put("/go/api/agents/#{agent.uuid}/disable") |> json_response(200)

      assert agent |> reload() |> Map.fetch!(:disabled) == true
    end
  end

  describe "encrypting a value with the server's key" do
    test "is refused to someone who is not an admin", %{conn: conn, member: member} do
      conn = conn |> Plug.Test.init_test_session(%{}) |> log_in_as(member.username)

      assert json_response(
               post(conn, "/go/api/admin/encrypt", %{"value" => "secret"}),
               :forbidden
             )
    end

    test "is allowed to an admin", %{conn: conn, admin: admin} do
      conn = conn |> Plug.Test.init_test_session(%{}) |> log_in_as(admin.username)

      body =
        conn
        |> post("/go/api/admin/encrypt", %{"value" => "secret"})
        |> json_response(200)

      assert body["encrypted_value"]
    end
  end

  defp reload(agent), do: Agents.get_agent_by_uuid(agent.uuid)
end
