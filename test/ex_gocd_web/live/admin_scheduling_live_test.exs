defmodule ExGoCDWeb.AdminSchedulingLiveTest do
  use ExGoCDWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ExGoCD.PipelinesFixtures

  alias ExGoCD.{Accounts, Agents, Repo}
  alias ExGoCD.Pipelines.{Job, Stage, Task}

  @agent_a_uuid "550e8400-e29b-41d4-a716-446655440001"
  @agent_b_uuid "550e8400-e29b-41d4-a716-446655440002"
  @agent_c_uuid "550e8400-e29b-41d4-a716-446655440003"

  setup do
    # Create admin user so admin_configured? returns true
    {:ok, _} =
      Accounts.create_user(%{
        username: "admin",
        display_name: "System Administrator",
        roles: ["admin"],
        status: "Active"
      })

    {:ok, _} =
      Accounts.create_user(%{
        username: "viewer",
        display_name: "Guest",
        roles: [],
        status: "Active"
      })

    # Register agents with different capabilities
    {:ok, _} =
      Agents.register_agent(%{
        uuid: @agent_a_uuid,
        hostname: "agent-linux",
        ipaddress: "10.0.0.1",
        resources: ["linux", "docker"],
        environments: [],
        state: "Idle"
      })

    {:ok, _} =
      Agents.register_agent(%{
        uuid: @agent_b_uuid,
        hostname: "agent-mac",
        ipaddress: "10.0.0.2",
        resources: ["mac", "docker"],
        environments: [],
        state: "Idle"
      })

    {:ok, _} =
      Agents.register_agent(%{
        uuid: @agent_c_uuid,
        hostname: "agent-gpu",
        ipaddress: "10.0.0.3",
        resources: ["gpu", "linux"],
        environments: [],
        state: "Building"
      })

    :ok
  end

  describe "AdminSchedulingLive page" do
    setup %{conn: conn} do
      {:ok, conn: log_in_as(conn, "admin")}
    end

    test "shows scheduling page with agent and job diagnostics", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/scheduling")

      # page renders diagnostic overview
      assert html =~ "agent-linux"
      assert html =~ "agent-mac"
      assert html =~ "agent-gpu"
      assert page_title(view) =~ "Scheduling"
    end

    test "shows all registered agents with their state and resources", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/scheduling")

      assert html =~ "agent-linux"
      assert html =~ "agent-mac"
      assert html =~ "agent-gpu"
      assert html =~ "Idle"
      assert html =~ "Building"
      assert html =~ "linux"
      assert html =~ "docker"
      assert html =~ "gpu"
    end

    test "shows pending jobs when there are scheduled JobInstances", %{conn: conn} do
      pipeline = insert_pipeline("test-pipe")

      stage =
        Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id}))

      job =
        Repo.insert!(%Job{} |> Job.changeset(%{name: "compile", stage_id: stage.id, resources: ["linux"]}))

      Repo.insert!(%Task{} |> Task.changeset(%{
        type: "exec", command: "echo", arguments: ["hello"], job_id: job.id
      }))

      now = DateTime.utc_now()
      pi = insert_pipeline_instance(pipeline.id, 1)
      si = insert_stage_instance(pi.id, "build", state: "Building", result: "Unknown")

      insert_job_instance_unassigned(si.id, "compile", now)

      {:ok, _view, html} = live(conn, ~p"/admin/scheduling")

      # page shows the scheduled job with its pipeline path and required resources
      assert html =~ "test-pipe/1/build/1/compile"
      assert html =~ "linux"
    end

    test "shows matching agents for a pending job", %{conn: conn} do
      pipeline = insert_pipeline("match-test")

      stage =
        Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id}))

      job =
        Repo.insert!(%Job{} |> Job.changeset(%{name: "test", stage_id: stage.id, resources: ["linux"]}))

      Repo.insert!(%Task{} |> Task.changeset(%{
        type: "exec", command: "echo", arguments: ["test"], job_id: job.id
      }))

      now = DateTime.utc_now()
      pi = insert_pipeline_instance(pipeline.id, 1)
      si = insert_stage_instance(pi.id, "build", state: "Building", result: "Unknown")

      insert_job_instance_unassigned(si.id, "test", now)

      {:ok, _view, html} = live(conn, ~p"/admin/scheduling")

      # idle agent with matching resources appears as available
      assert html =~ "agent-linux"
      assert html =~ "Ready to assign"
    end

    test "shows stuck reason when no agent has required resources", %{conn: conn} do
      pipeline = insert_pipeline("stuck-test")

      stage =
        Repo.insert!(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: pipeline.id}))

      job =
        Repo.insert!(%Job{} |> Job.changeset(%{name: "ai-train", stage_id: stage.id, resources: ["tpu", "v100"]}))

      Repo.insert!(%Task{} |> Task.changeset(%{
        type: "exec", command: "python", arguments: ["train.py"], job_id: job.id
      }))

      now = DateTime.utc_now()
      pi = insert_pipeline_instance(pipeline.id, 1)
      si = insert_stage_instance(pi.id, "build", state: "Building", result: "Unknown")

      insert_job_instance_unassigned(si.id, "ai-train", now)

      {:ok, _view, html} = live(conn, ~p"/admin/scheduling")

      assert html =~ "stuck-test/1/build/1/ai-train"
      assert html =~ "tpu"
      assert html =~ "v100"
      # No agent has tpu AND v100 → stuck
      assert html =~ "No agent has all required resources"
      refute html =~ "Ready to assign"
    end

    test "handles refresh event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/scheduling")

      html = render(view)
      assert html =~ "Scheduling Diagnostics"

      view
      |> element("button", "↻ Refresh")
      |> render_click()

      html = render(view)
      assert html =~ "Scheduling Diagnostics"
    end
  end

  describe "admin access control" do
    test "redirects non-admin users", %{conn: conn} do
      conn = log_in_as(conn, "viewer")
      {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/scheduling")
    end
  end
end
