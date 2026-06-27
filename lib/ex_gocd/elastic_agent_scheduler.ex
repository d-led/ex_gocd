defmodule ExGoCD.ElasticAgentScheduler do
  @moduledoc """
  Manages elastic agent pod lifecycle for Kubernetes.

  Mirrors GoCD's kubernetes-elastic-agents plugin architecture:
  - ServerPingRequestExecutor: periodic ping checks for pending jobs without agents
  - CreateAgentRequest → pod creation → agent registration → job execution
  - On job completion + idle timeout → pod deletion

  ## Lifecycle

  1. Tick (every 30s): find pending `run_on_all_agents` jobs with no matching agent
  2. Match elastic agent profile → cluster profile → build pod spec
  3. Create pod via K8s API → agent auto-registers → picks up job
  4. Track pod in state. On subsequent ticks:
     - If agent is Idle > 5 min → delete pod
     - If pod is in error state → delete pod
  """
  use GenServer
  require Logger

  alias ExGoCD.Agents
  alias ExGoCD.ClusterProfiles
  alias ExGoCD.ElasticAgentProfiles
  alias ExGoCD.ElasticAgentProfiles.ElasticAgentProfile
  alias ExGoCD.ClusterProfiles.ClusterProfile
  alias ExGoCD.K8s
  alias ExGoCD.Scheduler

  @tick_ms 30_000
  @idle_timeout_seconds 300

  # ── Client API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Return tracked pods (for admin UI)."
  def tracked_pods do
    GenServer.call(__MODULE__, :tracked_pods)
  end

  # ── Server callbacks ───────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    if enabled?() do
      schedule_tick()
    end

    {:ok, %{pods: %{}, tick_timer: nil}}
  end

  @impl true
  def handle_call(:tracked_pods, _from, state) do
    {:reply, state.pods, state}
  end

  @impl true
  def handle_info(:tick, state) do
    state = cleanup_idle_pods(state)
    state = check_and_scale(state)
    schedule_tick()
    {:noreply, state}
  end

  # ── Tick logic ─────────────────────────────────────────────────────────────

  defp check_and_scale(state) do
    pending_jobs = get_pending_run_on_all_jobs()

    Enum.reduce(pending_jobs, state, fn job, acc ->
      if needs_elastic_agent?(job) do
        acc
        |> maybe_create_pod(job)
        |> tap(fn
          %{pods: pods} when map_size(pods) > map_size(acc.pods) ->
            Logger.info("[ElasticAgentScheduler] Created pod for job: #{inspect(job_name(job))}")

          _ ->
            :ok
        end)
      else
        acc
      end
    end)
  end

  # ── Pod lifecycle ──────────────────────────────────────────────────────────

  defp maybe_create_pod(state, job) do
    resources = job[:resources] || job["resources"] || []

    case find_matching_profile(resources) do
      nil ->
        Logger.debug(
          "[ElasticAgentScheduler] No elastic agent profile matches resources: #{inspect(resources)}"
        )

        state

      {agent_profile, cluster_profile} ->
        {:ok, pod_spec} = build_pod_spec(agent_profile, cluster_profile, job, resources)
        conn = build_k8s_conn(cluster_profile)

        if is_nil(conn) do
          Logger.warning(
            "[ElasticAgentScheduler] Cannot build K8s connection — cluster profile may be incomplete"
          )

          state
        else
          namespace = ClusterProfile.namespace(cluster_profile)

          case K8s.create_pod(conn, pod_spec, namespace: namespace) do
            {:ok, pod_name} ->
              track_pod(state, pod_name, agent_profile, cluster_profile, job)

            {:error, reason} ->
              Logger.warning("[ElasticAgentScheduler] Failed to create pod: #{inspect(reason)}")

              state
          end
        end
    end
  end

  defp cleanup_idle_pods(state) do
    {to_delete, remaining} =
      Enum.split_with(state.pods, fn {_pod_name, info} ->
        idle_too_long?(info) or pod_in_error?(info)
      end)

    Enum.each(to_delete, fn {pod_name, info} ->
      conn = build_k8s_conn_from_pod(info)
      namespace = info[:namespace] || "default"
      K8s.delete_pod(conn, pod_name, namespace: namespace)
      Logger.info("[ElasticAgentScheduler] Deleted idle/error pod: #{pod_name}")
    end)

    %{state | pods: Map.new(remaining)}
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
      # Pod created but agent hasn't registered yet — check timeout
      created_at = info[:created_at] || DateTime.utc_now()
      DateTime.diff(DateTime.utc_now(), created_at) > 600
    end
  end

  defp pod_in_error?(info) do
    info[:error] == true
  end

  defp track_pod(state, pod_name, agent_profile, cluster_profile, job) do
    pods =
      Map.put(state.pods, pod_name, %{
        pod_name: pod_name,
        profile_name: agent_profile.name,
        cluster_name: cluster_profile.name,
        namespace: ClusterProfile.namespace(cluster_profile),
        job_name: job_name(job),
        resources: job[:resources] || job["resources"] || [],
        created_at: DateTime.utc_now(),
        agent_uuid: nil,
        error: false
      })

    %{state | pods: pods}
  end

  # ── Job inspection ─────────────────────────────────────────────────────────

  defp get_pending_run_on_all_jobs do
    # Inspect the scheduler queue for run_on_all_agents entries
    case Scheduler.get_queue_state() do
      %{in_memory_jobs: jobs} ->
        Enum.filter(jobs, fn job ->
          Map.get(job, :run_on_all_agents) == true or Map.get(job, "run_on_all_agents") == true
        end)

      _ ->
        []
    end
  end

  defp needs_elastic_agent?(job) do
    resources = job[:resources] || job["resources"] || []

    matching =
      Agents.find_agents_for_job(%{resources: resources, environments: job[:environments] || []})

    Enum.empty?(matching)
  end

  defp job_name(job) do
    job[:job] || job["job"] || "unknown"
  end

  # ── Profile matching ───────────────────────────────────────────────────────

  defp find_matching_profile(resources) do
    profiles = ElasticAgentProfiles.list_profiles()

    profile =
      if resources == [] do
        List.first(profiles)
      else
        # Match by resource affinity: prefer profiles that match job resources
        Enum.find(profiles, fn p ->
          profile_resources = Map.get(p.properties || %{}, "Resources", [])
          Enum.any?(resources, &(&1 in profile_resources))
        end) || List.first(profiles)
      end

    case profile do
      nil ->
        nil

      p ->
        cluster = ClusterProfiles.get_profile(p.cluster_profile_id)
        if cluster, do: {p, cluster}, else: nil
    end
  end

  # ── Pod spec builder ───────────────────────────────────────────────────────

  defp build_pod_spec(agent_profile, _cluster_profile, job, resources) do
    image = ElasticAgentProfile.image(agent_profile)
    name = "gocd-elastic-#{agent_profile.name}-#{random_suffix()}"
    pull_policy = ElasticAgentProfile.image_pull_policy(agent_profile)

    env_vars =
      [
        %{"name" => "GO_SERVER_URL", "value" => server_url()},
        %{"name" => "AGENT_AUTO_REGISTER_RESOURCES", "value" => Enum.join(resources, ",")},
        %{"name" => "AGENT_AUTO_REGISTER_ENVIRONMENTS", "value" => env_string(job)},
        %{"name" => "AGENT_HOSTNAME", "value" => name}
      ] ++ ElasticAgentProfile.env_vars(agent_profile)

    privileged = ElasticAgentProfile.privileged(agent_profile) == "true"
    service_account = ElasticAgentProfile.service_account(agent_profile)
    node_selector = ElasticAgentProfile.node_selector(agent_profile)
    pod_annotations = ElasticAgentProfile.pod_annotations(agent_profile)

    spec = %{
      "metadata" => %{
        "name" => name,
        "labels" => %{
          "app" => "gocd-elastic-agent",
          "gocd-profile" => agent_profile.name,
          "gocd-cluster" => agent_profile.cluster_profile_id
        }
      },
      "spec" => %{
        "containers" => [
          %{
            "name" => "gocd-agent",
            "image" => image,
            "imagePullPolicy" => pull_policy,
            "env" => env_vars,
            "resources" => %{
              "requests" => %{
                "memory" => ElasticAgentProfile.min_memory(agent_profile),
                "cpu" => ElasticAgentProfile.min_cpu(agent_profile)
              },
              "limits" => %{
                "memory" => ElasticAgentProfile.max_memory(agent_profile),
                "cpu" => ElasticAgentProfile.max_cpu(agent_profile)
              }
            },
            "securityContext" => %{
              "privileged" => privileged
            }
          }
        ],
        "restartPolicy" => "Never"
      }
    }

    spec = if service_account != "" do
      put_in(spec, ["spec", "serviceAccountName"], service_account)
    else
      spec
    end

    spec = if map_size(node_selector) > 0 do
      put_in(spec, ["spec", "nodeSelector"], node_selector)
    else
      spec
    end

    spec = if map_size(pod_annotations) > 0 do
      put_in(spec, ["metadata", "annotations"], pod_annotations)
    else
      spec
    end

    {:ok, spec}
  end

  # ── K8s connection helpers ─────────────────────────────────────────────────

  defp build_k8s_conn(cluster_profile) do
    config = %{
      "server" => ClusterProfile.server_url(cluster_profile) || "",
      "token" => ClusterProfile.bearer_token(cluster_profile) || "",
      "ca_cert" => ClusterProfile.ca_cert(cluster_profile),
      "namespace" => ClusterProfile.namespace(cluster_profile)
    }

    case K8s.from_config(config) do
      {:ok, conn} -> conn
      {:error, _} -> nil
    end
  end

  defp build_k8s_conn_from_pod(info) do
    cluster_name = info[:cluster_name]
    cluster = Enum.find(ClusterProfiles.list_profiles(), &(&1.name == cluster_name))

    if cluster do
      build_k8s_conn(cluster)
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp enabled? do
    Application.get_env(:ex_gocd, :elastic_agent_scheduler_enabled, true)
  end

  defp server_url do
    Application.get_env(:ex_gocd, :elastic_agent_server_url) ||
      "http://host.docker.internal:8153/go"
  end

  defp env_string(job) do
    envs = job[:environments] || job["environments"] || []
    Enum.join(envs, ",")
  end

  defp random_suffix do
    6
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(case: :lower)
    |> binary_part(0, 5)
  end
end
