# Copyright 2026 ex_gocd
# Simulated agent running inside the OTP cluster for scale testing.
# Emulates Go agent lifecycle (heartbeat pings, work assignment, preparing/building/completed reports).

defmodule ExGoCD.TestAgent do
  use GenServer

  alias ExGoCD.Agents
  alias ExGoCD.Scheduler
  alias ExGoCD.TestAgent.UUID
  alias ExGoCDWeb.AgentPresence

  @presence_topic "agent"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    uuid = opts[:uuid] || UUID.uuid4()
    hostname = opts[:hostname] || "mock-agent-#{String.slice(uuid, 0, 8)}"
    ip_address = opts[:ip_address] || "127.0.0.1"
    ping_interval = opts[:ping_interval] || 5000
    work_simulation_ms = opts[:work_simulation_ms] || 1000

    # Ensure agent is registered in the DB (configured & enabled)
    {:ok, agent} =
      Agents.register_agent(%{
        "uuid" => uuid,
        "hostname" => hostname,
        "ipaddress" => ip_address,
        "resources" => opts[:resources] || ["simulated"],
        "environments" => opts[:environments] || ["test"],
        "cookie" => "ex-gocd-demo-cookie"
      })

    # Auto-enable the agent if it was registered but disabled
    if agent.disabled do
      {:ok, _} = Agents.enable_agent(agent)
    end

    # Track presence so the scheduler and UI know this agent is connected
    {:ok, _} =
      AgentPresence.track(self(), @presence_topic, uuid, %{
        pid: inspect(self()),
        joined_at: System.system_time(:second)
      })

    # Subscribe to PubSub topic for this agent to receive builds/cancels
    Phoenix.PubSub.subscribe(ExGoCD.PubSub, "agent:" <> uuid)

    state = %{
      uuid: uuid,
      hostname: hostname,
      ip_address: ip_address,
      ping_interval: ping_interval,
      work_simulation_ms: work_simulation_ms,
      runtime_status: "Idle",
      current_build_id: nil,
      work_task: nil
    }

    # Register initial ping
    send(self(), :ping)

    {:ok, state}
  end

  @impl true
  def handle_info(:ping, state) do
    # Perform heartbeat update in database
    _ =
      Agents.touch_agent_on_heartbeat(state.uuid, %{
        "runtimeStatus" => state.runtime_status,
        "operatingSystem" => "Simulated OTP",
        "freeSpace" => 1024 * 1024 * 1024
      })

    # If idle, request work from the scheduler
    if state.runtime_status == "Idle" do
      _ = Scheduler.try_assign_work(state.uuid)
    end

    # Schedule next ping
    Process.send_after(self(), :ping, state.ping_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info({:build, build_payload}, state) do
    build_id = build_payload["buildId"]

    # 1. Update state to Building
    Agents.update_agent_runtime_state(state.uuid, "Building")

    # 2. Report Preparing
    ExGoCD.AgentJobRuns.handle_agent_report(state.uuid, %{
      "buildId" => build_id,
      "jobState" => "Preparing",
      "agentRuntimeInfo" => %{"runtimeStatus" => "Building"}
    })

    # 3. Simulate work execution asynchronously to avoid blocking GenServer pings/cancels
    parent = self()
    sim_time = state.work_simulation_ms
    uuid = state.uuid

    work_task =
      spawn(fn ->
        # Transition Preparing -> Building
        Process.sleep(div(sim_time, 3))

        ExGoCD.AgentJobRuns.handle_agent_report(uuid, %{
          "buildId" => build_id,
          "jobState" => "Building",
          "agentRuntimeInfo" => %{"runtimeStatus" => "Building"}
        })

        # Upload some mock logs to console
        ExGoCD.AgentJobRuns.append_console(build_id, "Preparing build workspace...\n")
        Process.sleep(div(sim_time, 3))
        ExGoCD.AgentJobRuns.append_console(build_id, "Executing simulated tasks...\n")
        Process.sleep(div(sim_time, 3))
        ExGoCD.AgentJobRuns.append_console(build_id, "Simulated build successfully finished!\n")

        # Transition Building -> Completed
        ExGoCD.AgentJobRuns.handle_agent_report(uuid, %{
          "buildId" => build_id,
          "jobState" => "Completed",
          "result" => "Passed",
          "agentRuntimeInfo" => %{"runtimeStatus" => "Idle"}
        })

        send(parent, {:work_done, build_id})
      end)

    {:noreply,
     %{state | runtime_status: "Building", current_build_id: build_id, work_task: work_task}}
  end

  @impl true
  def handle_info({:work_done, build_id}, state) do
    if state.current_build_id == build_id do
      # Back to idle
      Agents.update_agent_runtime_state(state.uuid, "Idle")
      _ = Scheduler.try_assign_work(state.uuid)
      {:noreply, %{state | runtime_status: "Idle", current_build_id: nil, work_task: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:cancel_build, build_id}, state) do
    if state.current_build_id == build_id do
      # Terminate active simulation process if running
      if state.work_task && Process.alive?(state.work_task) do
        Process.exit(state.work_task, :kill)
      end

      # Mark Completed / Cancelled
      ExGoCD.AgentJobRuns.handle_agent_report(state.uuid, %{
        "buildId" => build_id,
        "jobState" => "Completed",
        "result" => "Cancelled",
        "agentRuntimeInfo" => %{"runtimeStatus" => "Idle"}
      })

      Agents.update_agent_runtime_state(state.uuid, "Idle")
      _ = Scheduler.try_assign_work(state.uuid)
      {:noreply, %{state | runtime_status: "Idle", current_build_id: nil, work_task: nil}}
    else
      {:noreply, state}
    end
  end

  # Helper module to generate uuid if needed
  defmodule UUID do
    def uuid4 do
      binary = :crypto.strong_rand_bytes(16)
      <<u0::48, _::4, u1::12, _::2, u2::62>> = binary
      # Version 4, variant 1
      <<u0::48, 4::4, u1::12, 2::2, u2::62>>
      |> Base.encode16(case: :lower)
      |> format_uuid()
    end

    defp format_uuid(<<a::8-bytes, b::4-bytes, c::4-bytes, d::4-bytes, e::12-bytes>>) do
      "#{a}-#{b}-#{c}-#{d}-#{e}"
    end
  end
end
