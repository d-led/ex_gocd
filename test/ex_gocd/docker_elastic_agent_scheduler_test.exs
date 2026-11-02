defmodule ExGoCD.DockerElasticAgentSchedulerTest do
  @moduledoc """
  The Docker elastic scheduler had no test: every decision it makes ends in a
  Docker API call, and the calls are made directly. What can be checked without a
  daemon is checked here — the image a job's resources pick, and the public view of
  a scheduler with nothing running. The tick itself (idle cleanup, scaling,
  maintaining a minimum) still needs the Docker calls behind a seam.

  The scheduler is a cluster singleton, so this runs synchronously.
  """
  use ExGoCD.DataCase, async: false

  alias ExGoCD.DockerElasticAgentScheduler, as: Scheduler
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

      def create_container(_image, _env, _opts) do
        report({:create, nil, []})
        {:error, :unused}
      end

      def start_container(cid, opts), do: report({:start, cid, opts})

      defp report(call) do
        if pid = Process.get(:docker_reporter), do: send(pid, {:docker, call})
        :ok
      end
    end

    setup do
      previous = Application.get_env(:ex_gocd, :docker_client)
      Application.put_env(:ex_gocd, :docker_client, FakeDocker)
      Process.put(:docker_reporter, self())
      on_exit(fn -> Application.put_env(:ex_gocd, :docker_client, previous) end)
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
