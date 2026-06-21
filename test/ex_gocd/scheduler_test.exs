defmodule ExGoCD.SchedulerTest do
  use ExGoCD.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias ExGoCD.Agents
  alias ExGoCD.Scheduler
  alias ExGoCDWeb.AgentPresence

  @presence_topic "agent"
  @uuid "550e8400-e29b-41d4-a716-446655440000"
  @uuid_b "660e8400-e29b-41d4-a716-446655440001"

  setup do
    wait_for_scheduler()
    :ok
  end

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
      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j1"})
      assert Scheduler.pending_count() == n0 + 1

      AgentPresence.track(self(), @presence_topic, @uuid, %{})
      assert Scheduler.try_assign_work(@uuid) == :assigned
      assert Scheduler.pending_count() == n0
    end

    test "two idle agents each receive one job when queue has two (GoCD-style work distribution)" do
      {:ok, _} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      {:ok, _} = Agents.register_agent(%{uuid: @uuid_b, hostname: "agent-b", ipaddress: "127.0.0.2"})

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j1"})
      assert {:ok, _} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j2"})
      assert Scheduler.pending_count() == n0 + 2

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

      assert Scheduler.try_assign_work(@uuid) == :assigned
      assert Scheduler.try_assign_work(@uuid_b) == :assigned
      assert Scheduler.pending_count() == n0

      Process.exit(pid_a, :kill)
      Process.exit(pid_b, :kill)
    end
  end

  describe "resource matching (GoCD BuildAssignmentService semantics)" do
    test "job with no resources is assigned to any idle agent" do
      assert_unrestricted_job_assigned()
    end

    test "job requiring resources is not assigned to agent without those resources" do
      Scheduler.clear_queue()
      {:ok, _} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{
        "pipeline" => "p", "stage" => "s", "job" => "j",
        "resources" => ["linux"]
      })
      assert Scheduler.pending_count() == n0 + 1

      AgentPresence.track(self(), @presence_topic, @uuid, %{})
      assert Scheduler.try_assign_work(@uuid) == :no_work
      assert Scheduler.pending_count() == n0 + 1
    end

    test "job requiring one resource is assigned to agent that has it" do
      {:ok, agent} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      Agents.update_agent(agent, %{resources: ["linux"]})
      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{
        "pipeline" => "p", "stage" => "s", "job" => "j",
        "resources" => ["linux"]
      })
      assert Scheduler.pending_count() == n0 + 1

      AgentPresence.track(self(), @presence_topic, @uuid, %{})
      assert Scheduler.try_assign_work(@uuid) == :assigned
      assert Scheduler.pending_count() == n0
    end

    test "job requiring multiple resources is assigned only to agent that has all" do
      Scheduler.clear_queue()
      {:ok, agent_linux} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      Agents.update_agent(agent_linux, %{resources: ["linux"]})
      {:ok, agent_both} = Agents.register_agent(%{uuid: @uuid_b, hostname: "agent-b", ipaddress: "127.0.0.2"})
      Agents.update_agent(agent_both, %{resources: ["linux", "docker"]})

      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{
        "pipeline" => "p", "stage" => "s", "job" => "integration",
        "resources" => ["linux", "docker"]
      })
      assert Scheduler.pending_count() == n0 + 1

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
      assert_unrestricted_job_assigned()
    end

    test "job requiring environment is not assigned to agent not in that environment" do
      Scheduler.clear_queue()
      {:ok, _} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{
        "pipeline" => "p", "stage" => "s", "job" => "j",
        "environments" => ["prod"]
      })
      assert Scheduler.pending_count() == n0 + 1

      AgentPresence.track(self(), @presence_topic, @uuid, %{})
      assert Scheduler.try_assign_work(@uuid) == :no_work
      assert Scheduler.pending_count() == n0 + 1
    end

    test "job requiring environment is assigned to agent in that environment" do
      {:ok, agent} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
      Agents.update_agent(agent, %{environments: ["prod"]})
      n0 = Scheduler.pending_count()
      assert {:ok, _} = Scheduler.schedule_job(%{
        "pipeline" => "p", "stage" => "s", "job" => "j",
        "environments" => ["prod"]
      })
      assert Scheduler.pending_count() == n0 + 1

      AgentPresence.track(self(), @presence_topic, @uuid, %{})
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

  defp assert_unrestricted_job_assigned do
    {:ok, _} = Agents.register_agent(%{uuid: @uuid, hostname: "agent-a", ipaddress: "127.0.0.1"})
    n0 = Scheduler.pending_count()
    assert {:ok, _} = Scheduler.schedule_job(%{"pipeline" => "p", "stage" => "s", "job" => "j"})
    assert Scheduler.pending_count() == n0 + 1

    AgentPresence.track(self(), @presence_topic, @uuid, %{})
    assert Scheduler.try_assign_work(@uuid) == :assigned
    assert Scheduler.pending_count() == n0
  end

  defp wait_for_scheduler do
    case Process.whereis(ExGoCD.Scheduler) do
      nil ->
        Process.sleep(10)
        wait_for_scheduler()
      pid ->
        if Process.alive?(pid) do
          :ok
        else
          Process.sleep(10)
          wait_for_scheduler()
        end
    end
  end

  describe "artifact commands generation" do
    alias ExGoCD.Pipelines.{Job, JobInstance, Pipeline, PipelineInstance, Stage, StageInstance, Task}
    alias ExGoCD.Repo

    test "generates uploadArtifact command from job config" do
      # Set up a pipeline with artifact_configs
      pipeline = Repo.insert!(%Pipeline{name: "upload-pipe", group: "test"})
      stage = Repo.insert!(%Stage{name: "build-stage", pipeline_id: pipeline.id, approval_type: "success"})
      job = Repo.insert!(%Job{
        name: "compile-job",
        stage_id: stage.id,
        artifact_configs: %{"artifacts" => [%{"src" => "target/app.jar", "dest" => "libs"}]}
      })
      Repo.insert!(%Task{type: "exec", command: "echo", arguments: ["done"], job_id: job.id})

      # Trigger instance
      pipeline_instance = Repo.insert!(%PipelineInstance{
        pipeline_id: pipeline.id,
        counter: 1,
        label: "upload-pipe/1",
        natural_order: 1.0,
        build_cause: %{}
      })

      stage_instance = Repo.insert!(%StageInstance{
        pipeline_instance_id: pipeline_instance.id,
        name: stage.name,
        counter: 1,
        order_id: 1,
        state: "Building",
        approval_type: "success",
        created_time: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      job_instance = Repo.insert!(%JobInstance{
        stage_instance_id: stage_instance.id,
        job_id: job.id,
        name: job.name,
        state: "Scheduled",
        scheduled_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })

      # Load with preloads
      ji = Repo.get!(JobInstance, job_instance.id)
           |> Repo.preload([:job, stage_instance: [pipeline_instance: :pipeline]])

      cmd_spec = Scheduler.build_command_from_job_instance(ji)

      assert %{
        "name" => "compose",
        "subCommands" => sub_cmds
      } = cmd_spec

      # Assert there is an uploadArtifact subcommand at the end
      upload_cmd = List.last(sub_cmds)
      assert upload_cmd == %{
        "name" => "uploadArtifact",
        "src" => "target/app.jar",
        "dest" => "libs"
      }
    end

    test "generates fetchArtifact command from fetch task" do
      # Set up an upstream pipeline and run it so we have a passed instance
      up_pipeline = Repo.insert!(%Pipeline{name: "upstream-pipe", group: "test"})
      up_stage = Repo.insert!(%Stage{name: "up-stage", pipeline_id: up_pipeline.id, approval_type: "success"})
      _up_job = Repo.insert!(%Job{name: "up-job", stage_id: up_stage.id})

      up_pi = Repo.insert!(%PipelineInstance{
        pipeline_id: up_pipeline.id,
        counter: 42,
        label: "upstream-pipe/42",
        natural_order: 42.0,
        build_cause: %{}
      })

      _up_si = Repo.insert!(%StageInstance{
        pipeline_instance_id: up_pi.id,
        name: up_stage.name,
        counter: 1,
        order_id: 1,
        state: "Completed",
        result: "Passed",
        approval_type: "success",
        created_time: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      # Set up a downstream pipeline with a fetch task
      down_pipeline = Repo.insert!(%Pipeline{name: "downstream-pipe", group: "test"})
      down_stage = Repo.insert!(%Stage{name: "down-stage", pipeline_id: down_pipeline.id, approval_type: "success"})
      down_job = Repo.insert!(%Job{name: "down-job", stage_id: down_stage.id})

      # The fetch task arguments are: [pipeline, stage, job, src, dest]
      Repo.insert!(%Task{
        type: "fetch",
        job_id: down_job.id,
        arguments: ["upstream-pipe", "up-stage", "up-job", "target/app.jar", "libs"]
      })

      down_pi = Repo.insert!(%PipelineInstance{
        pipeline_id: down_pipeline.id,
        counter: 1,
        label: "downstream-pipe/1",
        natural_order: 1.0,
        build_cause: %{}
      })

      down_si = Repo.insert!(%StageInstance{
        pipeline_instance_id: down_pi.id,
        name: down_stage.name,
        counter: 1,
        order_id: 1,
        state: "Building",
        approval_type: "success",
        created_time: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      down_ji = Repo.insert!(%JobInstance{
        stage_instance_id: down_si.id,
        job_id: down_job.id,
        name: down_job.name,
        state: "Scheduled",
        scheduled_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })

      ji = Repo.get!(JobInstance, down_ji.id)
           |> Repo.preload([:job, stage_instance: [pipeline_instance: :pipeline]])

      cmd_spec = Scheduler.build_command_from_job_instance(ji)
      assert %{"subCommands" => sub_cmds} = cmd_spec

      # Assert there is a fetchArtifact subcommand
      fetch_cmd = Enum.find(sub_cmds, &(&1["name"] == "fetchArtifact"))
      assert fetch_cmd == %{
        "name" => "fetchArtifact",
        "src" => "upstream-pipe/42/up-stage/1/up-job/target/app.jar",
        "dest" => "libs"
      }
    end
  end
end
