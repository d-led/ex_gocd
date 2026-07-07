defmodule ExGoCD.DockerElasticAgentScheduler do
  @moduledoc """
  Manages elastic agent container lifecycle for Docker.

  Mirrors ElasticAgentScheduler but uses the Docker Engine API instead of K8s:
  - Tick (every 30s): find pending jobs without matching static agents
  - Match Docker elastic agent profile → pick image from ResourceImages mapping
  - Create container → agent auto-registers → picks up job
  - On job completion + idle timeout → stop + remove container

  ## Resource→Image Mapping

  When a job requests resources (e.g. "java", "python"), the scheduler looks
  up the `ResourceImages` map in the profile properties:

      {"java": "myorg/gocd-agent-java:21", "python": "myorg/gocd-agent-python:3.12"}

  Falls back to the profile's `Image` if no resource matches.
  """
  use GenServer
  use ExGoCD.GenServerRedact

  alias ExGoCD.Agents
  alias ExGoCD.Docker
  alias ExGoCD.ElasticAgentProfiles
  alias ExGoCD.ElasticAgentProfiles.ElasticAgentProfile

  @tick_ms 30_000
  @idle_timeout_seconds 300
  @max_events 50

  @docker_plugin_id "cd.go.contrib.elastic-agent.docker"

  # ── Client API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    ExGoCD.DistSingleton.start_link(__MODULE__, opts)
  end

  @doc "Return tracked containers (for admin UI)."
  def tracked_containers do
    GenServer.call(ExGoCD.DistSingleton.via_horde(__MODULE__), :tracked_containers)
  end

  @doc "Return recent scheduler events (for admin UI)."
  def recent_events do
    GenServer.call(ExGoCD.DistSingleton.via_horde(__MODULE__), :recent_events)
  end

  @doc "Delete all tracked containers and return count."
  def delete_all_containers do
    GenServer.call(ExGoCD.DistSingleton.via_horde(__MODULE__), :delete_all_containers)
  end

  # ── Server callbacks ───────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    if enabled?() do
      schedule_tick()
    end

    {:ok, %{containers: %{}, events: [], tick_timer: nil}}
  end

  @impl true
  def handle_call(:tracked_containers, _from, state) do
    {:reply, state.containers, state}
  end

  def handle_call(:recent_events, _from, state) do
    {:reply, state.events, state}
  end

  def handle_call(:delete_all_containers, _from, state) do
    count = map_size(state.containers)

    state =
      Enum.reduce(state.containers, state, fn {cid, info}, acc ->
        socket = info[:docker_socket]
        Docker.stop_container(cid, docker_socket: socket)
        Docker.remove_container(cid, docker_socket: socket)
        acc
      end)

    {:reply, count, %{state | containers: %{}}}
  end

  @impl true
  def handle_info(:tick, state) do
    state =
      try do
        state
        |> cleanup_idle_containers()
        |> check_and_scale()
        |> maintain_min_agents()
      rescue
        e ->
          log_event(state, :error, "Tick error: #{Exception.message(e)}")
          state
      end

    schedule_tick()
    {:noreply, state}
  end

  # ── Tick logic ─────────────────────────────────────────────────────────────

  defp check_and_scale(state) do
    profiles = docker_profiles()

    if profiles == [] do
      state
    else
      pending_jobs = get_pending_jobs()
      Enum.reduce(pending_jobs, state, &maybe_scale_for_job(&2, &1, profiles))
    end
  end

  defp maybe_scale_for_job(acc, job, profiles) do
    if needs_docker_agent?(job) do
      acc
      |> maybe_create_container(job, profiles)
      |> tap(fn
        %{containers: cs} when map_size(cs) > map_size(acc.containers) ->
          log_event(acc, :info, "Created container for job #{job_name(job)}")

        _ ->
          :ok
      end)
    else
      acc
    end
  end

  # ── Minimum agents ─────────────────────────────────────────────────────────

  defp maintain_min_agents(state) do
    Enum.reduce(docker_profiles(), state, fn profile, acc ->
      min = ElasticAgentProfile.min_agents(profile)
      if min <= 0, do: acc, else: ensure_min_containers(acc, profile, min)
    end)
  end

  defp ensure_min_containers(state, profile, min) do
    profile_containers =
      Enum.count(state.containers, fn {_cid, info} -> info[:profile_name] == profile.name end)

    if profile_containers >= min do
      state
    else
      socket = docker_socket_for_profile(profile)
      create_min_containers(state, profile, socket, min - profile_containers)
    end
  end

  defp create_min_containers(state, profile, socket, count) do
    Enum.reduce(1..count, state, fn i, acc ->
      label = "standby-#{i}"
      image = ElasticAgentProfile.image(profile)
      env = build_env(%{job: label, resources: []})

      case Docker.create_container(image, env,
             docker_socket: socket,
             memory: ElasticAgentProfile.max_memory(profile),
             cpu: ElasticAgentProfile.max_cpu(profile),
             name: "gocd-elastic-#{profile.name}-#{label}",
             labels: %{"profile" => profile.name}
           ) do
        {:ok, container_id} ->
          Docker.start_container(container_id, docker_socket: socket)

          track_container(acc, container_id, profile, %{
            job: label,
            resources: [],
            docker_socket: socket
          })
          |> then(fn s ->
            log_event(s, :info, "Created standby container for profile #{profile.name}")
          end)

        {:error, reason} ->
          log_event(acc, :error, "Failed to create standby container: #{reason}")
      end
    end)
  end

  # ── Container lifecycle ────────────────────────────────────────────────────

  defp maybe_create_container(state, job, profiles) do
    resources = job[:resources] || job["resources"] || []

    case find_matching_profile(resources, profiles) do
      nil ->
        log_event(state, :info, "No Docker profile matches resources: #{inspect(resources)}")

      profile ->
        image = pick_image(profile, resources)
        socket = docker_socket_for_profile(profile)
        env = build_env(job)

        case Docker.create_container(image, env,
               docker_socket: socket,
               memory: ElasticAgentProfile.max_memory(profile),
               cpu: ElasticAgentProfile.max_cpu(profile),
               labels: %{"profile" => profile.name}
             ) do
          {:ok, container_id} ->
            Docker.start_container(container_id, docker_socket: socket)
            track_container(state, container_id, profile, Map.put(job, :docker_socket, socket))

          {:error, reason} ->
            log_event(state, :error, "Failed to create container: #{reason}")
        end
    end
  end

  defp cleanup_idle_containers(state) do
    {to_delete, remaining} =
      Enum.split_with(state.containers, fn {_cid, info} ->
        idle_too_long?(info) or container_in_error?(info)
      end)

    state =
      Enum.reduce(to_delete, state, fn {cid, info}, acc ->
        socket = info[:docker_socket]
        Docker.stop_container(cid, docker_socket: socket)
        Docker.remove_container(cid, docker_socket: socket)
        log_event(acc, :info, "Deleted idle/error container: #{String.slice(cid, 0, 12)}")
      end)

    %{state | containers: Map.new(remaining)}
  end

  defp idle_too_long?(info) do
    agent_uuid = info[:agent_uuid]

    if agent_uuid do
      case Agents.get_agent_by_uuid(agent_uuid) do
        %{state: "Idle", updated_at: updated_at} ->
          idle_seconds = DateTime.diff(DateTime.utc_now(), updated_at)
          idle_seconds > @idle_timeout_seconds

        _ ->
          false
      end
    else
      created_at = info[:created_at] || DateTime.utc_now()
      DateTime.diff(DateTime.utc_now(), created_at) > 600
    end
  end

  defp container_in_error?(info) do
    info[:error] == true
  end

  # ── Profile matching ───────────────────────────────────────────────────────

  defp docker_profiles do
    ElasticAgentProfiles.list_profiles()
    |> Enum.filter(&(&1.plugin_id == @docker_plugin_id))
  end

  defp find_matching_profile(resources, profiles) do
    if resources == [] do
      # For no-resource jobs, prefer the explicitly-named no-resources profile
      Enum.find(profiles, &(&1.name == "docker-no-resources")) || List.first(profiles)
    else
      # Prefer profiles whose ResourceImages or resources match the job
      Enum.find(profiles, fn p ->
        resource_images = Map.get(p.properties || %{}, "ResourceImages", %{})
        profile_resources = Map.get(p.properties || %{}, "Resources", [])

        Enum.any?(resources, &(&1 in profile_resources)) or
          Enum.any?(resources, &Map.has_key?(resource_images, &1))
      end) || List.first(profiles)
    end
  end

  @doc """
  Picks the Docker image for a given resource set.

  Looks up `ResourceImages` map in the profile properties. If any job
  resource matches a key in the map, that value is used as the image.
  Falls back to the profile's `Image` property.
  """
  def pick_image(profile, resources) do
    resource_images = Map.get(profile.properties || %{}, "ResourceImages", %{})

    # Find the first resource that has a mapped image
    image =
      Enum.find_value(resources, fn r ->
        Map.get(resource_images, r)
      end) || ElasticAgentProfile.image(profile)

    image
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp build_env(job) do
    resources = job[:resources] || job["resources"] || []
    environments = job[:environments] || job["environments"] || []

    %{
      "AGENT_SERVER_URL" => docker_server_url(),
      "AGENT_AUTO_REGISTER_KEY" => agent_cookie(),
      "AGENT_AUTO_REGISTER_RESOURCES" => Enum.join(resources, ","),
      "AGENT_AUTO_REGISTER_ENVIRONMENTS" => Enum.join(environments, ","),
      "AGENT_AUTO_REGISTER_HOSTNAME" => job_name(job)
    }
  end

  defp docker_server_url do
    # Inside a Docker container on macOS, host.docker.internal reaches the host
    base =
      System.get_env("EX_GOCD_DOCKER_URL") || System.get_env("EX_GOCD_URL") ||
        "http://localhost:4000"

    if :os.type() == {:unix, :darwin} do
      # On macOS Docker Desktop, replace localhost with host.docker.internal
      String.replace(base, "localhost", "host.docker.internal")
    else
      base
    end
  end

  defp agent_cookie do
    System.get_env("AGENT_AUTO_REGISTER_KEY") || "ex-gocd-demo-cookie"
  end

  defp docker_socket_for_profile(profile) do
    # Docker profiles don't have a cluster profile — they use local Docker socket.
    # The socket can be overridden via the profile properties.
    Map.get(profile.properties || %{}, "DockerSocket") || Docker.default_socket()
  end

  defp enabled? do
    System.get_env("DOCKER_ELASTIC_ENABLED") != "false"
  end

  defp track_container(state, container_id, profile, job) do
    containers =
      Map.put(state.containers, container_id, %{
        container_id: container_id,
        profile_name: profile.name,
        image: pick_image(profile, job[:resources] || []),
        job_name: job_name(job),
        resources: job[:resources] || [],
        created_at: DateTime.utc_now(),
        agent_uuid: nil,
        error: false
      })

    %{state | containers: containers}
  end

  defp job_name(job) do
    job[:job] || job["job"] || "unknown"
  end

  defp needs_docker_agent?(job) do
    resources = job[:resources] || job["resources"] || []

    matching =
      Agents.find_agents_for_job(%{resources: resources, environments: job[:environments] || []})

    Enum.empty?(matching)
  end

  defp get_pending_jobs do
    case ExGoCD.Scheduler.get_queue_state() do
      %{in_memory_jobs: jobs} -> jobs
      _ -> []
    end
  rescue
    _ -> []
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp log_event(state, level, message) do
    events =
      [%{level: level, message: message, time: DateTime.utc_now()} | state.events]
      |> Enum.take(@max_events)

    %{state | events: events}
  end
end
