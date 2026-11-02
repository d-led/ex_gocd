defmodule ExGoCD.DockerTest do
  @moduledoc """
  The Docker client has no seam short of its socket, so these tests are the
  daemon: a stub on a Unix socket answers what the test decides and hands back
  the request it was sent.

  `default_socket/0` is not exercised here. What it decides is which environment
  variable wins, and mutating the environment is exactly what keeps the suite
  from running tests in parallel.
  """
  use ExUnit.Case, async: true

  alias ExGoCD.Docker
  alias ExGoCD.DockerDaemonStub

  describe "ping/1" do
    test "answers :ok when the daemon is there" do
      daemon = DockerDaemonStub.serving(status: 200, body: "OK")

      assert Docker.ping(docker_socket: daemon.socket) == :ok
    end

    test "asks the ping path" do
      daemon = DockerDaemonStub.serving(status: 200, body: "OK")

      Docker.ping(docker_socket: daemon.socket)

      assert %{method: "GET", path: "/_ping"} = DockerDaemonStub.request(daemon)
    end

    test "names the code when the daemon is there but unhappy" do
      daemon = DockerDaemonStub.serving(status: 500, body: "{}")

      assert Docker.ping(docker_socket: daemon.socket) ==
               {:error, "Docker ping returned HTTP 500"}
    end

    test "says the daemon is unreachable when nothing listens" do
      nowhere =
        Path.join(System.tmp_dir!(), "no-daemon-#{System.unique_integer([:positive])}.sock")

      assert {:error, "Docker unreachable: " <> _} = Docker.ping(docker_socket: nowhere)
    end
  end

  describe "create_container/3" do
    test "answers with the id the daemon assigned" do
      daemon = DockerDaemonStub.serving(status: 201, body: %{"Id" => "c0ffee"})

      assert Docker.create_container("alpine:3.20", %{}, docker_socket: daemon.socket) ==
               {:ok, "c0ffee"}
    end

    test "tells the daemon the image, the environment, the resources and the labels" do
      daemon = DockerDaemonStub.serving(status: 201, body: %{"Id" => "c0ffee"})

      Docker.create_container("eclipse-temurin:21", %{"GO_PIPELINE_NAME" => "build"},
        docker_socket: daemon.socket,
        memory: "512m",
        cpu: "1.5",
        labels: %{"pipeline" => "build"}
      )

      body = daemon |> DockerDaemonStub.request() |> Map.fetch!(:body) |> Jason.decode!()

      assert body["Image"] == "eclipse-temurin:21"
      assert body["Env"] == ["GO_PIPELINE_NAME=build"]
      assert body["HostConfig"]["Memory"] == 512 * 1024 * 1024
      assert body["HostConfig"]["NanoCPUs"] == 1_500_000_000
      assert body["HostConfig"]["AutoRemove"] == true
      assert body["Labels"] == %{"app" => "gocd-elastic-agent", "pipeline" => "build"}
    end

    test "names the container for the elastic agents unless told otherwise" do
      daemon = DockerDaemonStub.serving(status: 201, body: %{"Id" => "c0ffee"})

      Docker.create_container("alpine", %{}, docker_socket: daemon.socket)

      path = DockerDaemonStub.request(daemon).path
      assert "name=gocd-elastic-" <> _suffix = URI.parse(path).query
    end

    test "gives the container the name it was asked for" do
      daemon = DockerDaemonStub.serving(status: 201, body: %{"Id" => "c0ffee"})

      Docker.create_container("alpine", %{}, docker_socket: daemon.socket, name: "agent-7")

      assert DockerDaemonStub.request(daemon).path == "/containers/create?name=agent-7"
    end

    test "passes on the daemon's reason for refusing" do
      daemon =
        DockerDaemonStub.serving(
          status: 404,
          body: %{"message" => "No such image: alpine:nope"}
        )

      assert Docker.create_container("alpine:nope", %{}, docker_socket: daemon.socket) ==
               {:error, "No such image: alpine:nope"}
    end

    test "falls back to the profile default when the daemon cannot read a quantity" do
      daemon = DockerDaemonStub.serving(status: 201, body: %{"Id" => "c0ffee"})

      Docker.create_container("alpine", %{},
        docker_socket: daemon.socket,
        memory: "plenty",
        cpu: "lots"
      )

      host = daemon |> request_host_config()

      assert host["Memory"] == 2_147_483_648
      assert host["NanoCPUs"] == 2_000_000_000
    end

    test "reads the units a profile may write as the same amount" do
      for written <- ["4Gi", "4G", "4GB"] do
        daemon = DockerDaemonStub.serving(status: 201, body: %{"Id" => "c0ffee"})

        Docker.create_container("alpine", %{}, docker_socket: daemon.socket, memory: written)

        assert request_host_config(daemon)["Memory"] == 4 * 1024 * 1024 * 1024,
               ~s("#{written}" was read as something other than 4 GiB)
      end
    end
  end

  describe "start_container/2" do
    test "answers :ok when the daemon started it" do
      daemon = DockerDaemonStub.serving(status: 204)

      assert Docker.start_container("c0ffee", docker_socket: daemon.socket) == :ok
      assert DockerDaemonStub.request(daemon).path == "/containers/c0ffee/start"
    end

    test "answers :ok when it was already running" do
      daemon = DockerDaemonStub.serving(status: 304)

      assert Docker.start_container("c0ffee", docker_socket: daemon.socket) == :ok
    end

    test "passes on the daemon's reason for refusing" do
      daemon = DockerDaemonStub.serving(status: 500, body: %{"message" => "driver failed"})

      assert Docker.start_container("c0ffee", docker_socket: daemon.socket) ==
               {:error, "driver failed"}
    end
  end

  describe "stop_container/2" do
    test "answers :ok when the daemon stopped it" do
      daemon = DockerDaemonStub.serving(status: 204)

      assert Docker.stop_container("c0ffee", docker_socket: daemon.socket) == :ok
      assert DockerDaemonStub.request(daemon).path == "/containers/c0ffee/stop"
    end

    test "answers :ok when it was already stopped" do
      daemon = DockerDaemonStub.serving(status: 304)

      assert Docker.stop_container("c0ffee", docker_socket: daemon.socket) == :ok
    end

    test "passes on the daemon's reason for refusing" do
      daemon = DockerDaemonStub.serving(status: 500, body: %{"message" => "no such container"})

      assert Docker.stop_container("c0ffee", docker_socket: daemon.socket) ==
               {:error, "no such container"}
    end
  end

  describe "remove_container/2" do
    test "answers :ok when the daemon removed it, forcing a running one out of the way" do
      daemon = DockerDaemonStub.serving(status: 204)

      assert Docker.remove_container("c0ffee", docker_socket: daemon.socket) == :ok
      assert DockerDaemonStub.request(daemon).path == "/containers/c0ffee?force=true"
    end

    test "passes on the daemon's reason for refusing" do
      daemon = DockerDaemonStub.serving(status: 404, body: %{"message" => "No such container"})

      assert Docker.remove_container("c0ffee", docker_socket: daemon.socket) ==
               {:error, "No such container"}
    end
  end

  describe "list_containers/2" do
    test "returns what the daemon reports" do
      containers = [%{"Id" => "a"}, %{"Id" => "b"}]
      daemon = DockerDaemonStub.serving(status: 200, body: containers)

      assert Docker.list_containers(%{}, docker_socket: daemon.socket) == {:ok, containers}
    end

    test "asks for the labels it was given as Docker's one filter parameter" do
      daemon = DockerDaemonStub.serving(status: 200, body: [])

      Docker.list_containers(%{"app" => "gocd-elastic-agent"}, docker_socket: daemon.socket)

      filters = URI.encode(Jason.encode!(%{label: ["app=gocd-elastic-agent"]}))
      assert DockerDaemonStub.request(daemon).path == "/containers/json?filters=" <> filters
    end

    test "names the code when the daemon would not list" do
      daemon = DockerDaemonStub.serving(status: 500, body: "{}")

      assert Docker.list_containers(%{}, docker_socket: daemon.socket) ==
               {:error, "Docker list failed: HTTP 500"}
    end

    test "says the daemon is unreachable when nothing listens" do
      nowhere =
        Path.join(System.tmp_dir!(), "no-daemon-#{System.unique_integer([:positive])}.sock")

      assert {:error, "Docker list failed: " <> _} =
               Docker.list_containers(%{}, docker_socket: nowhere)
    end
  end

  describe "list_all_containers/1" do
    test "asks the daemon for the stopped containers too" do
      daemon = DockerDaemonStub.serving(status: 200, body: [])

      assert Docker.list_all_containers(docker_socket: daemon.socket) == {:ok, []}
      assert DockerDaemonStub.request(daemon).path == "/containers/json?all=true"
    end
  end

  defp request_host_config(daemon) do
    daemon
    |> DockerDaemonStub.request()
    |> Map.fetch!(:body)
    |> Jason.decode!()
    |> Map.fetch!("HostConfig")
  end
end
