defmodule ExGoCD.ElasticAgentSchedulerTest do
  @moduledoc """
  The Kubernetes elastic scheduler makes every decision by calling the Kubernetes
  API, so the calls go through `ElasticAgentScheduler.k8s/0` and the tests replace
  that client. What a tick does is then checked without a cluster: a queued job
  becomes the pod its profile describes, a pod in error is deleted, a pod nothing
  tracks is reaped, and a cluster that refuses a pod says why.

  The scheduler is a cluster singleton, so this runs synchronously.
  """
  use ExGoCD.DataCase, async: false

  alias ExGoCD.Agents
  alias ExGoCD.ClusterProfiles
  alias ExGoCD.ElasticAgentProfiles
  alias ExGoCD.ElasticAgentScheduler

  @uuid "e2e00000-e29b-41d4-a716-446655440001"

  defmodule FakeK8s do
    @moduledoc false
    def from_kubeconfig(_yaml), do: {:ok, :fake_conn}
    def from_config(_config), do: {:ok, :fake_conn}

    # A test decides whether the cluster accepts a pod by putting `:ok` (a fresh
    # name per call) or an error tuple under :k8s_create.
    def create_pod(conn, spec, opts) do
      report({:create, conn, spec, opts})

      case Process.get(:k8s_create, {:error, :denied}) do
        :ok -> {:ok, fresh_pod_name()}
        error -> error
      end
    end

    def delete_pod(conn, name, opts) do
      report({:delete, conn, name, opts})
      :ok
    end

    def list_pods(conn, opts) do
      report({:list, conn, nil, opts})
      {:ok, Process.get(:k8s_pods, [])}
    end

    defp report(call) do
      if pid = Process.get(:k8s_reporter), do: send(pid, {:k8s, call})
      :ok
    end

    defp fresh_pod_name do
      count = Process.get(:k8s_pod_count, 0) + 1
      Process.put(:k8s_pod_count, count)
      "pod#{count}"
    end
  end

  defmodule FakeQueue do
    @moduledoc false
    def get_queue_state, do: %{in_memory_jobs: Process.get(:queue_answer, [])}
  end

  setup do
    replace = fn key, value ->
      previous = Application.get_env(:ex_gocd, key)
      Application.put_env(:ex_gocd, key, value)
      on_exit(fn -> Application.put_env(:ex_gocd, key, previous) end)
    end

    replace.(:k8s_client, FakeK8s)
    replace.(:elastic_scheduler_queue, FakeQueue)
    Process.put(:k8s_reporter, self())
    :ok
  end

  describe "the tick" do
    test "a queued job no static agent can run becomes a pod its profile shapes" do
      {:ok, _profile} =
        kubernetes_profile("builders", %{
          "Image" => "gocd-agent:1",
          "MaxMemory" => "4Gi",
          "Resources" => ["docker"]
        })

      Process.put(:k8s_create, :ok)
      Process.put(:queue_answer, [%{job: "build", resources: ["docker"], environments: []}])

      assert {:noreply, new_state} = ElasticAgentScheduler.handle_info(:tick, fresh_state())

      assert_received {:k8s, {:create, :fake_conn, spec, opts}}
      assert opts[:namespace] == "ci"

      assert [container] = spec["spec"]["containers"]
      assert container["image"] == "gocd-agent:1"
      assert container["resources"]["limits"]["memory"] == "4Gi"
      assert spec["metadata"]["labels"]["gocd-profile"] == "builders"

      assert [pod] = Map.values(new_state.pods)
      assert pod.job_name == "build"
      assert pod.namespace == "ci"
      assert Enum.any?(new_state.events, &(&1.message == "Created pod for job build"))
    end

    test "a job a static agent can already run gets no pod" do
      {:ok, _profile} = kubernetes_profile("builders", %{"Image" => "gocd-agent:1"})
      Process.put(:k8s_create, :ok)
      Process.put(:queue_answer, [%{job: "build", resources: ["docker"], environments: []}])

      {:ok, _agent} =
        Agents.register_agent(%{
          uuid: @uuid,
          hostname: "static-host",
          ipaddress: "10.0.0.9",
          resources: ["docker"]
        })

      assert {:noreply, new_state} = ElasticAgentScheduler.handle_info(:tick, fresh_state())

      assert new_state.pods == %{}
      refute_received {:k8s, {:create, _, _, _}}
    end

    test "with no profile configured a queued job gets no pod and the reason is logged" do
      Process.put(:k8s_create, :ok)
      Process.put(:queue_answer, [%{job: "build", resources: ["docker"], environments: []}])

      assert {:noreply, new_state} = ElasticAgentScheduler.handle_info(:tick, fresh_state())

      assert new_state.pods == %{}
      refute_received {:k8s, {:create, _, _, _}}

      assert Enum.any?(new_state.events, &(&1.message =~ "No elastic profile matches resources"))
    end

    test "a cluster that refuses the pod logs why and tracks nothing" do
      {:ok, _profile} = kubernetes_profile("builders", %{"Image" => "gocd-agent:1"})
      Process.put(:k8s_create, {:error, %{status: 403}})
      Process.put(:queue_answer, [%{job: "build", resources: [], environments: []}])

      assert {:noreply, new_state} = ElasticAgentScheduler.handle_info(:tick, fresh_state())

      assert new_state.pods == %{}
      assert Enum.any?(new_state.events, &(&1.message =~ "Failed to create pod"))
    end

    test "a pod in error is deleted and forgotten" do
      {:ok, cluster} = kubernetes_cluster()

      state = %{
        pods: %{"pod-in-error" => %{error: true, cluster_name: cluster.name, namespace: "ci"}},
        events: [],
        tick_timer: nil
      }

      assert {:noreply, new_state} = ElasticAgentScheduler.handle_info(:tick, state)

      assert_received {:k8s, {:delete, :fake_conn, "pod-in-error", [namespace: "ci"]}}
      assert new_state.pods == %{}
      assert Enum.any?(new_state.events, &(&1.message =~ "Deleted idle/error pod"))
    end

    test "a pod the cluster still has but nothing tracks is reaped" do
      {:ok, _profile} = kubernetes_profile("builders", %{"Image" => "gocd-agent:1"})

      Process.put(:k8s_pods, [
        %{
          name: "forgotten-pod",
          labels: %{"app" => "gocd-elastic-agent"},
          created_at: DateTime.add(DateTime.utc_now(), -900, :second)
        }
      ])

      assert {:noreply, new_state} = ElasticAgentScheduler.handle_info(:tick, fresh_state())

      assert_received {:k8s, {:delete, :fake_conn, "forgotten-pod", [namespace: "ci"]}}
      assert Enum.any?(new_state.events, &(&1.message =~ "Reaped orphan pod forgotten-pod"))
    end

    defp fresh_state, do: %{pods: %{}, events: [], tick_timer: nil}
  end

  describe "what the admin view asks for" do
    setup do
      {:ok, cluster} = kubernetes_cluster()

      pod = %{
        pod_name: "pod1",
        profile_name: "builders",
        job_name: "build",
        namespace: "ci",
        cluster_name: cluster.name
      }

      %{state: %{pods: %{"pod1" => pod}, events: [], tick_timer: nil}}
    end

    test "names the pods it tracks", %{state: state} do
      assert {:reply, pods, ^state} = ElasticAgentScheduler.handle_call(:tracked_pods, nil, state)
      assert Map.keys(pods) == ["pod1"]
    end

    test "names the events it logged", %{state: state} do
      logged = %{state | events: [%{level: :info, message: "Deleted idle/error pod: pod1"}]}

      assert {:reply, [event], ^logged} =
               ElasticAgentScheduler.handle_call(:recent_events, nil, logged)

      assert event.message == "Deleted idle/error pod: pod1"
    end

    test "deleting everything removes each pod and says how many", %{state: state} do
      assert {:reply, 1, emptied} =
               ElasticAgentScheduler.handle_call(:delete_all_pods, nil, state)

      assert_received {:k8s, {:delete, :fake_conn, "pod1", _opts}}
      assert emptied.pods == %{}
    end

    test "deleting everything when nothing is tracked says none" do
      empty = %{pods: %{}, events: [], tick_timer: nil}

      assert {:reply, 0, ^empty} = ElasticAgentScheduler.handle_call(:delete_all_pods, nil, empty)
    end
  end

  defp kubernetes_cluster(name \\ "test-cluster") do
    ClusterProfiles.create_profile(%{
      name: name,
      plugin_id: "ex_gocd.elasticagent.kubernetes",
      properties: %{"kubernetes_cluster_url" => "https://k8s.test:6443", "namespace" => "ci"}
    })
  end

  defp kubernetes_profile(name, properties) do
    {:ok, cluster} = kubernetes_cluster()

    ElasticAgentProfiles.create_profile(%{
      name: name,
      plugin_id: "ex_gocd.elasticagent.kubernetes",
      cluster_profile_id: cluster.id,
      properties: properties
    })
  end
end
