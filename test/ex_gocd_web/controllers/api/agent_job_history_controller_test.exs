defmodule ExGoCDWeb.API.AgentJobHistoryControllerTest do
  @moduledoc """
  An agent's job history. The report is only worth reading if it says what the
  run went through, so these tests drive real runs through their states and read
  the answer back, and they pin the four query parameters GoCD rejects rather
  than letting a bad one silently return a different page.
  """
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Accounts
  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Agents

  @agent_uuid "550e8400-e29b-41d4-a716-446655500077"

  setup %{conn: conn} do
    {:ok, _} =
      Agents.register_agent(%{uuid: @agent_uuid, hostname: "hist-agent", ipaddress: "10.0.0.7"})

    {:ok, admin} =
      Accounts.create_user(%{
        username: "hist-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> log_in_as(admin.username)

    %{conn: conn}
  end

  describe "GET /go/api/agents/:uuid/job_run_history" do
    test "says which states the job went through, and when", %{conn: conn} do
      run_a_job_through(["Preparing", "Building"], "Passed")

      body = conn |> get("/go/api/agents/#{@agent_uuid}/job_run_history") |> json_response(200)

      assert body["uuid"] == @agent_uuid

      assert [job] = body["jobs"]
      assert job["pipeline_name"] == "history-pipeline"
      assert job["stage_name"] == "build"
      assert job["job_name"] == "compile"
      assert job["pipeline_counter"] == 1
      assert job["stage_counter"] == "1"
      assert job["result"] == "Passed"

      assert Enum.map(job["job_state_transitions"], & &1["state"]) ==
               ["Assigned", "Preparing", "Building", "Completed"]

      assert Enum.all?(job["job_state_transitions"], &(&1["state_change_time"] =~ "T"))
    end

    test "leaves out runs that have not finished", %{conn: conn} do
      {:ok, _} = AgentJobRuns.create_run(@agent_uuid, "still-running", "p", "s", "j")

      body = conn |> get("/go/api/agents/#{@agent_uuid}/job_run_history") |> json_response(200)

      assert body["jobs"] == []
      assert body["pagination"]["total"] == 0
    end

    test "pages by offset and page_size, and counts every completed run", %{conn: conn} do
      for n <- 1..3, do: run_a_job_through([], "Passed", build_id: "run-#{n}")

      body =
        conn
        |> get("/go/api/agents/#{@agent_uuid}/job_run_history?offset=1&page_size=10")
        |> json_response(200)

      assert body["pagination"] == %{"page_size" => 10, "offset" => 1, "total" => 3}
      assert length(body["jobs"]) == 2
    end

    test "sorts by the column and order asked for", %{conn: conn} do
      run_a_job_through([], "Passed", build_id: "a-run", job_name: "zulu")
      run_a_job_through([], "Failed", build_id: "b-run", job_name: "alpha")

      body =
        conn
        |> get("/go/api/agents/#{@agent_uuid}/job_run_history?sort_column=job&sort_order=ASC")
        |> json_response(200)

      assert Enum.map(body["jobs"], & &1["job_name"]) == ["alpha", "zulu"]
    end

    test "refuses a page_size outside 10..100 rather than returning another page", %{conn: conn} do
      body =
        conn
        |> get("/go/api/agents/#{@agent_uuid}/job_run_history?page_size=5")
        |> json_response(400)

      assert body["message"] ==
               "The query parameter `page_size`, if specified must be a number between 10 and 100."
    end

    test "refuses a sort column it cannot sort by, naming the ones it can", %{conn: conn} do
      body =
        conn
        |> get("/go/api/agents/#{@agent_uuid}/job_run_history?sort_column=colour")
        |> json_response(400)

      assert body["message"] ==
               "The query parameter `sort_column` must be one of pipeline, stage, job, result, completed, duration"
    end

    test "refuses a negative offset", %{conn: conn} do
      body =
        conn
        |> get("/go/api/agents/#{@agent_uuid}/job_run_history?offset=-1")
        |> json_response(400)

      assert body["message"] =~
               "The query parameter `offset`, if specified must be a number greater or equal to 0."
    end

    test "says an agent it cannot find is missing", %{conn: conn} do
      unknown = Ecto.UUID.generate()

      body = conn |> get("/go/api/agents/#{unknown}/job_run_history") |> json_response(404)

      assert body["message"] == "Agent with identifier '#{unknown}' was not found."
    end

    test "is for admins, as in GoCD" do
      {:ok, member} =
        Accounts.create_user(%{
          username: "hist-member-#{System.unique_integer([:positive])}",
          display_name: "Member",
          roles: [],
          status: "Active"
        })

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> log_in_as(member.username)

      assert conn
             |> get("/go/api/agents/#{@agent_uuid}/job_run_history")
             |> json_response(:forbidden)
    end
  end

  # `create_run` + the reports an agent makes, which is the only way a history is
  # ever produced.
  defp run_a_job_through(states, result, opts \\ []) do
    build_id = Keyword.get(opts, :build_id, "history-build")
    job_name = Keyword.get(opts, :job_name, "compile")

    {:ok, _run} =
      AgentJobRuns.create_run(
        @agent_uuid,
        build_id,
        "history-pipeline",
        "build",
        job_name,
        stage_counter: 1
      )

    Enum.each(states, &AgentJobRuns.report_status(@agent_uuid, build_id, &1))
    {:ok, _} = AgentJobRuns.report_status(@agent_uuid, build_id, "Completed", result)
  end
end
