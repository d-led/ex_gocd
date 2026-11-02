defmodule ExGoCD.DockerElasticAgentSchedulerTest do
  @moduledoc """
  The Docker elastic scheduler makes every decision by calling the Docker API, so
  the calls go through `Scheduler.docker/0` and the tests replace that client. What
  a tick does is then checked without a daemon: a container in error is cleaned up,
  a healthy one is left alone, and a profile that asks for standby agents gets
  them.

  The scheduler is a cluster singleton, so this runs synchronously.
  """
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Agents
  alias ExGoCD.ClusterProfiles
  alias ExGoCD.DockerElasticAgentScheduler, as: Scheduler
  alias ExGoCD.ElasticAgentProfiles
  alias ExGoCD.ElasticAgentProfiles.ElasticAgentProfile

  defp profile(properties) do
    %ElasticAgentProfile{id: Ecto.UUID.generate(), properties: properties}
  end

  describe "pick_image/2" do
    test "takes the image of the first resource the profile maps" do
      profile =
        profile(%{"Image" => "default.png", "ResourceImages" => %{"docker" => "docker.png"}})

      assert Scheduler.pick_image(profile, ["linux", "docker"]) == "docker.png"
    end

    test "falls back to the profile's image when no resource is mapped" do
      profile =
        profile(%{"Image" => "default.png", "ResourceImages" => %{"docker" => "docker.png"}})

      assert Scheduler.pick_image(profile, ["linux"]) == "default.png"
    end

    test "falls back to the profile's image when nothing is mapped at all" do
      profile = profile(%{"Image" => "default.png"})

      assert Scheduler.pick_image(profile, ["docker"]) == "default.png"
    end

    test "a profile with no properties still names an image" do
      assert Scheduler.pick_image(profile(%{}), []) == ElasticAgentProfile.image(profile(%{}))
    end
  end

  describe "the tick, with the Docker client replaced" do
    defmodule FakeDocker do
      @moduledoc false
      def stop_container(cid, opts), do: report({:stop, cid, opts})
      def remove_container(cid, opts), do: report({:remove, cid, opts})
      def default_socket, do: "unix:///fake.sock"

      # A test decides whether the daemon accepts a container by putting `:ok` (a
      # fresh id per call) or an error tuple under :docker_create. Declining by
      # default keeps a tick that finds queued jobs from quietly adding containers.
      def create_container(image, env, opts) do
        report({:create, image, env, opts})

        case Process.get(:docker_create, {:error, :denied}) do
          :ok -> {:ok, fresh_container_id()}
          error -> error
        end
      end

      def start_container(cid, opts), do: report({:start, cid, opts})

      defp report(call) do
        if pid = Process.get(:docker_reporter), do: send(pid, {:docker, call})
        :ok
      end

      defp fresh_container_id do
        count = Process.get(:docker_container_count, 0) + 1
        Process.put(:docker_container_count, count)
        "container#{count}"
      end
    end

    defmodule FakeQueue do
      @moduledoc false
      def get_queue_state do
        case Process.get(:queue_answer, []) do
          :unreachable -> raise "the queue is unreachable"
          jobs -> %{in_memory_jobs: jobs}
        end
      end
    end

    setup do
      replace = fn key, value ->
        previous = Application.get_env(:ex_gocd, key)
        Application.put_env(:ex_gocd, key, value)
        on_exit(fn -> Application.put_env(:ex_gocd, key, previous) end)
      end

      replace.(:docker_client, FakeDocker)
      replace.(:elastic_scheduler_queue, FakeQueue)
      Process.put(:docker_reporter, self())
      :ok
    end

    test "a container in error is stopped, removed and forgotten" do
      state = %{
        containers: %{"abcd1234efgh" => %{error: true, docker_socket: "unix:///x.sock"}},
        events: [],
        tick_timer: nil
      }

      assert {:noreply, new_state} = Scheduler.handle_info(:tick, state)

      assert_received {:docker, {:stop, "abcd1234efgh", [docker_socket: "unix:///x.sock"]}}
      assert_received {:docker, {:remove, "abcd1234efgh", [docker_socket: "unix:///x.sock"]}}
      assert new_state.containers == %{}
      assert [%{level: :info, message: message} | _] = new_state.events
      assert message =~ "Deleted idle/error container"
    end

    test "a healthy new container is left alone" do
      state = %{
        containers: %{
          "healthy12345" => %{error: false, created_at: DateTime.utc_now(), docker_socket: nil}
        },
        events: [],
        tick_timer: nil
      }

      assert {:noreply, new_state} = Scheduler.handle_info(:tick, state)

      refute_received {:docker, {:stop, _, _}}
      assert Map.has_key?(new_state.containers, "healthy12345")
    end

    test "a queued job for resources no static agent has gets a container" do
      {:ok, _profile} =
        docker_profile("builders", %{"Resources" => ["docker"], "Image" => "agent:1"})

      Process.put(:docker_create, :ok)
      Process.put(:queue_answer, [%{job: "build", resources: ["docker"], environments: []}])

      assert {:noreply, new_state} = Scheduler.handle_info(:tick, fresh_state())

      assert [container] = Map.values(new_state.containers)
      assert container.job_name == "build"
      assert container.image == "agent:1"
      cid = container.container_id
      assert_received {:docker, {:start, ^cid, _opts}}
      assert Enum.any?(new_state.events, &(&1.message == "Created container for job build"))
    end

    test "a job a static agent can already run gets no container" do
      {:ok, _profile} =
        docker_profile("builders", %{"Resources" => ["docker"], "Image" => "agent:1"})

      Process.put(:docker_create, :ok)
      Process.put(:queue_answer, [%{job: "build", resources: ["docker"], environments: []}])

      {:ok, _agent} =
        Agents.register_agent(%{
          uuid: Ecto.UUID.generate(),
          hostname: "static-host",
          ipaddress: "10.0.0.9",
          resources: ["docker"]
        })

      assert {:noreply, new_state} = Scheduler.handle_info(:tick, fresh_state())

      assert new_state.containers == %{}
      refute_received {:docker, {:create, _, _, _}}
    end

    test "a queue that cannot be read is reported, not hidden" do
      {:ok, _profile} =
        docker_profile("builders", %{"Resources" => ["docker"], "Image" => "agent:1"})

      Process.put(:queue_answer, :unreachable)

      assert {:noreply, new_state} = Scheduler.handle_info(:tick, fresh_state())

      assert [%{level: :error, message: message} | _] = new_state.events
      assert message =~ "Tick error"
      assert message =~ "the queue is unreachable"
    end

    test "a profile that keeps standby agents gets that many created" do
      {:ok, _profile} = docker_profile("standby-pool", %{"MinAgents" => 2, "Image" => "agent:1"})
      Process.put(:docker_create, :ok)

      assert {:noreply, new_state} = Scheduler.handle_info(:tick, fresh_state())

      standbys = standby_containers(new_state)
      assert length(standbys) == 2
      assert Enum.all?(standbys, &(&1.profile_name == "standby-pool"))
      assert Enum.all?(standbys, &(&1.image == "agent:1"))
      assert_received {:docker, {:create, "agent:1", _env, _opts}}
      assert_received {:docker, {:start, "container1", _opts}}

      assert Enum.any?(
               new_state.events,
               &(&1.message =~ "Created standby container for profile standby-pool")
             )
    end

    test "a profile that asks for no standby agents creates none" do
      {:ok, _profile} = docker_profile("scale-to-zero", %{"Image" => "agent:1"})
      Process.put(:docker_create, :ok)

      assert {:noreply, new_state} = Scheduler.handle_info(:tick, fresh_state())

      assert standby_containers(new_state) == []
      refute Enum.any?(new_state.events, &(&1.message =~ "Created standby container"))
    end

    test "standby agents already running are not created twice" do
      {:ok, _profile} = docker_profile("standby-pool", %{"MinAgents" => 1, "Image" => "agent:1"})
      Process.put(:docker_create, :ok)

      assert {:noreply, once} = Scheduler.handle_info(:tick, fresh_state())
      assert length(standby_containers(once)) == 1

      assert {:noreply, twice} = Scheduler.handle_info(:tick, once)
      assert length(standby_containers(twice)) == 1
    end

    defp fresh_state, do: %{containers: %{}, events: [], tick_timer: nil}

    defp standby_containers(state) do
      for {_cid, info} <- state.containers,
          String.starts_with?(info.job_name, "standby-"),
          do: info
    end

    defp docker_profile(name, properties) do
      {:ok, cluster} =
        ClusterProfiles.create_profile(%{
          name: "#{name}-cluster",
          plugin_id: "cd.go.contrib.elastic-agent.docker",
          properties: %{"docker_socket" => "unix:///var/run/docker.sock"}
        })

      ElasticAgentProfiles.create_profile(%{
        name: name,
        plugin_id: "cd.go.contrib.elastic-agent.docker",
        cluster_profile_id: cluster.id,
        properties: properties
      })
    end
  end

  describe "a scheduler with nothing running" do
    test "tracks no containers" do
      assert Scheduler.tracked_containers() == %{}
    end

    test "has no events to report" do
      assert Scheduler.recent_events() == []
    end

    test "deleting all containers deletes none" do
      assert Scheduler.delete_all_containers() == 0
    end
  end
end
