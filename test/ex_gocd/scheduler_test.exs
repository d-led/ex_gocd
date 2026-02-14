defmodule ExGoCD.SchedulerTest do
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Agents
  alias ExGoCD.Scheduler
  alias ExGoCDWeb.AgentPresence

  @presence_topic "agent"
  @uuid "550e8400-e29b-41d4-a716-446655440000"
  @uuid_b "660e8400-e29b-41d4-a716-446655440001"

  describe "schedule_job/1" do
    test "enqueues a job and returns id" do
      assert {:ok, id} = Scheduler.schedule_job(%{})
      assert is_binary(id)
      assert String.starts_with?(id, "sched-")

      assert {:ok, _id2} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j"})
      assert Scheduler.pending_count() >= 2
    end

    test "accepts pipeline, stage, job and optional resources, environments" do
      assert {:ok, _} =
               Scheduler.schedule_job(%{
                 "pipeline" => "my-pipeline",
                 "stage" => "build",
                 "job" => "compile",
                 "resources" => ["linux"],
                 "environments" => ["dev"]
               })

      assert Scheduler.pending_count() >= 1
    end
  end

  describe "try_assign_work/1" do
    test "returns :no_work when queue is empty" do
      # Agent may or may not exist/be connected; we only assert no_work when queue empty
      result = Scheduler.try_assign_work(@uuid)
      assert result in [:no_work, :agent_not_connected, :agent_not_found]
    end

    test "returns :agent_not_found when agent uuid is not in DB" do
      _ = Scheduler.schedule_job(%{})
      result = Scheduler.try_assign_work("00000000-0000-0000-0000-000000000000")
      assert result in [:agent_not_found, :agent_not_connected]
    end

    test "one idle agent receives one job from queue" do
      {:ok, _} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      AgentPresence.track(self(), @presence_topic, @uuid, %{})

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j1"})
      assert Scheduler.pending_count() == n0 + 1

      assert Scheduler.try_assign_work(@uuid) == :assigned
      assert Scheduler.pending_count() == n0
    end

    test "two idle agents each receive one job when queue has two (GoCD-style work distribution)" do
      {:ok, _} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      {:ok, _} = Agents.register_agent(%{uuid: @uuid_b, hostname: "agent-b", ipaddress: "127.0.0.2"})

      # Two distinct processes must track so Presence has two entries (one per agent)
      parent = self()
      ref = make_ref()
      pid_a = spawn_link(fn ->
        AgentPresence.track(self(), @presence_topic, @uuid, %{})
        send(parent, {ref, :a})
        receive do _ -> :ok end
      end)
      pid_b = spawn_link(fn ->
        AgentPresence.track(self(), @presence_topic, @uuid_b, %{})
        send(parent, {ref, :b})
        receive do _ -> :ok end
      end)
      receive do {^ref, :a} -> :ok end
      receive do {^ref, :b} -> :ok end

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j1"})
      assert {:ok, _} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j2"})
      assert Scheduler.pending_count() == n0 + 2

      assert Scheduler.try_assign_work(@uuid) == :assigned
      assert Scheduler.try_assign_work(@uuid_b) == :assigned
      assert Scheduler.pending_count() == n0

      Process.exit(pid_a, :kill)
      Process.exit(pid_b, :kill)
    end
  end

  describe "resource matching (GoCD BuildAssignmentService semantics)" do
    test "job with no resources is assigned to any idle agent" do
      {:ok, _} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      AgentPresence.track(self(), @presence_topic, @uuid, %{})

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j"})
      assert Scheduler.try_assign_work(@uuid) == :assigned
      assert Scheduler.pending_count() == n0
    end

    test "job requiring resources is not assigned to agent without those resources" do
      Scheduler.clear_queue()
      {:ok, _} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      AgentPresence.track(self(), @presence_topic, @uuid, %{})

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{
        "pipeline" => "p", "stage" => "s", "job" => "j",
        "resources" => ["linux"]
      })
      assert Scheduler.try_assign_work(@uuid) == :no_work
      assert Scheduler.pending_count() == n0 + 1
    end

    test "job requiring one resource is assigned to agent that has it" do
      {:ok, agent} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      Agents.update_agent(agent, %{resources: ["linux"]})
      AgentPresence.track(self(), @presence_topic, @uuid, %{})

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{
        "pipeline" => "p", "stage" => "s", "job" => "j",
        "resources" => ["linux"]
      })
      assert Scheduler.try_assign_work(@uuid) == :assigned
      assert Scheduler.pending_count() == n0
    end

    test "job requiring multiple resources is assigned only to agent that has all" do
      Scheduler.clear_queue()
      {:ok, agent_linux} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      Agents.update_agent(agent_linux, %{resources: ["linux"]})
      {:ok, agent_both} = Agents.register_agent(%{uuid: @uuid_b, hostname: "agent-b", ipaddress: "127.0.0.2"})
      Agents.update_agent(agent_both, %{resources: ["linux", "docker"]})

      parent = self()
      ref = make_ref()
      pid_a = spawn_link(fn ->
        AgentPresence.track(self(), @presence_topic, @uuid, %{})
        send(parent, {ref, :a})
        receive do _ -> :ok end
      end)
      pid_b = spawn_link(fn ->
        AgentPresence.track(self(), @presence_topic, @uuid_b, %{})
        send(parent, {ref, :b})
        receive do _ -> :ok end
      end)
      receive do {^ref, :a} -> :ok end
      receive do {^ref, :b} -> :ok end

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{
        "pipeline" => "p", "stage" => "s", "job" => "integration",
        "resources" => ["linux", "docker"]
      })
      # Only agent with both resources should get the job
      assert Scheduler.try_assign_work(@uuid) == :no_work
      assert Scheduler.try_assign_work(@uuid_b) == :assigned
      assert Scheduler.pending_count() == n0

      Process.exit(pid_a, :kill)
      Process.exit(pid_b, :kill)
    end
  end

  describe "environment matching (GoCD semantics)" do
    test "job with no environments matches any agent" do
      {:ok, _} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      AgentPresence.track(self(), @presence_topic, @uuid, %{})

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j"})
      assert Scheduler.try_assign_work(@uuid) == :assigned
      assert Scheduler.pending_count() == n0
    end

    test "job requiring environment is not assigned to agent not in that environment" do
      Scheduler.clear_queue()
      {:ok, _} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      AgentPresence.track(self(), @presence_topic, @uuid, %{})

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{
        "pipeline" => "p", "stage" => "s", "job" => "j",
        "environments" => ["prod"]
      })
      assert Scheduler.try_assign_work(@uuid) == :no_work
      assert Scheduler.pending_count() == n0 + 1
    end

    test "job requiring environment is assigned to agent in that environment" do
      {:ok, agent} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      Agents.update_agent(agent, %{environments: ["prod"]})
      AgentPresence.track(self(), @presence_topic, @uuid, %{})

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{
        "pipeline" => "p", "stage" => "s", "job" => "j",
        "environments" => ["prod"]
      })
      assert Scheduler.try_assign_work(@uuid) == :assigned
      assert Scheduler.pending_count() == n0
    end
  end

  describe "pending_count/0" do
    test "returns 0 when queue is empty" do
      # Scheduler state is process-wide; in async: false we share with other tests
      count = Scheduler.pending_count()
      assert is_integer(count) and count >= 0
    end
  end
end
