# Copyright 2026 ex_gocd
# Controller for spawning simulated agents via HTTP for scalability testing.

defmodule ExGoCDWeb.API.TestController do
  use ExGoCDWeb, :controller

  def start_agents(conn, params) do
    repo_config = Application.get_env(:ex_gocd, ExGoCD.Repo) || []
    is_sandbox? = repo_config[:pool] == Ecto.Adapters.SQL.Sandbox

    if System.get_env("EX_GOCD_TEST_MODE") == "1" or is_sandbox? or
         Application.get_env(:ex_gocd, :env) == :dev do
      count_str = params["count"] || "100"

      count =
        case Integer.parse(count_str) do
          {n, _} -> n
          :error -> 100
        end

      Enum.each(1..count, fn _ ->
        ExGoCD.TestAgentSupervisor.start_agent(
          resources: ["simulated", "otp"],
          environments: ["test"],
          ping_interval: 2000,
          work_simulation_ms: 1000
        )
      end)

      json(conn, %{message: "Started #{count} simulated agents."})
    else
      conn
      |> put_status(403)
      |> json(%{error: "Forbidden: Test mode is not enabled."})
    end
  end

  def start_http_agents(conn, params) do
    repo_config = Application.get_env(:ex_gocd, ExGoCD.Repo) || []
    is_sandbox? = repo_config[:pool] == Ecto.Adapters.SQL.Sandbox

    if System.get_env("EX_GOCD_TEST_MODE") == "1" or is_sandbox? or
         Application.get_env(:ex_gocd, :env) == :dev do
      count_str = params["count"] || "1"

      count =
        case Integer.parse(count_str) do
          {n, _} -> n
          :error -> 1
        end

      port = conn.port
      host = conn.host

      Enum.each(1..count, fn _ ->
        ExGoCD.TestAgentSupervisor.start_http_agent(
          host: host,
          port: port,
          ping_interval: 2000
        )
      end)

      json(conn, %{message: "Started #{count} HTTP simulated agents."})
    else
      conn
      |> put_status(403)
      |> json(%{error: "Forbidden: Test mode is not enabled."})
    end
  end
end
