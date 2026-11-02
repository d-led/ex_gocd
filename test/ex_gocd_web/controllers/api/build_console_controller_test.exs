defmodule ExGoCDWeb.API.BuildConsoleControllerTest do
  @moduledoc """
  The agent posts console chunks here and the dashboard shows what was stored, so
  this endpoint decides what a secret in a log line is allowed to reach.

  It read the body with `case read_body(conn) do {:ok, ...} -> ... end`, and
  `read_body/1` answers `{:more, partial, conn}` once a body passes 8 MB, so a
  large chunk raised `CaseClauseError` instead of answering. The view already had
  an `error_413/1` nobody could reach.
  """
  use ExGoCDWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.Agents
  alias ExGoCD.Repo

  @agent_uuid "550e8400-e29b-41d4-a716-446655440000"
  @build_id "build-with-console"

  setup do
    {:ok, _} =
      Agents.register_agent(%{
        uuid: @agent_uuid,
        hostname: "console-agent",
        ipaddress: "192.168.1.2"
      })

    {:ok, _run} =
      AgentJobRuns.create_run(@agent_uuid, @build_id, "deploy", "build", "compile")

    %{}
  end

  describe "POST /api/builds/:build_id/console" do
    test "a chunk reaches the run's console", %{conn: conn} do
      conn = post_console(conn, @build_id, "Compiling 3 files\n")

      assert conn.status == 204
      assert console(@build_id) == "Compiling 3 files\n"
    end

    test "a secret in a chunk never reaches the console", %{conn: conn} do
      post_console(
        conn,
        @build_id,
        "TOKEN=ghp_abcdefghijklmnopqrstuvwxyz0123456789\nCompiling 3 files\n"
      )

      console = console(@build_id)

      refute console =~ "ghp_abcdefghijklmnopqrstuvwxyz0123456789"
      assert console =~ "Compiling 3 files"
    end

    test "a build nobody has is missing", %{conn: conn} do
      conn = post_console(conn, "build-that-never-was", "text\n")

      assert json_response(conn, 404) == %{"error" => "run not found"}
    end

    test "a chunk over the read limit is refused, not crashed", %{conn: conn} do
      conn = post_console(conn, @build_id, String.duplicate("x", 8_000_001))

      assert json_response(conn, 413) == %{"error" => "payload too large"}
      assert console(@build_id) == ""
    end
  end

  defp post_console(conn, build_id, body) do
    conn
    |> put_req_header("content-type", "text/plain")
    |> post("/api/builds/#{build_id}/console", body)
  end

  defp console(build_id) do
    Repo.one(from r in AgentJobRun, where: r.build_id == ^build_id, select: r.console_log)
  end
end
