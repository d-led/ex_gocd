defmodule ExGoCD.K8sTest do
  use ExUnit.Case, async: true

  # DynamicHTTPProvider needs a running k8s application context;
  # skipped on CI until we fix the mock integration properly.
  @moduletag :ci_skip

  # Fully-qualified atom to avoid ExGoCD.K8s module shadowing
  @dynamic_provider :"Elixir.K8s.Client.DynamicHTTPProvider"

  defmodule HTTPMock do
    @pod_path "/api/v1/namespaces/default/pods"

    def request(:post, %URI{path: @pod_path}, _body, _headers, _opts) do
      {:ok, %{"metadata" => %{"name" => "gocd-agent-test"}}}
    end

    def request(:get, %URI{path: @pod_path}, _body, _headers, _opts) do
      {:ok,
       %{
         "items" => [
           %{"metadata" => %{"name" => "pod-1", "labels" => %{"app" => "gocd-agent"}}, "status" => %{"phase" => "Running", "hostIP" => "10.0.0.1"}},
           %{"metadata" => %{"name" => "pod-2", "labels" => %{}}, "status" => %{"phase" => "Pending"}}
         ]
       }}
    end

    def request(:delete, %URI{path: @pod_path <> "/" <> _}, _body, _headers, _opts) do
      {:ok, %{"status" => "Success"}}
    end
  end

  setup do
    @dynamic_provider.register(self(), HTTPMock)
    :ok
  end

  describe "from_config/1" do
    test "creates a conn from server and token" do
      assert {:ok, conn} = ExGoCD.K8s.from_config(%{"server" => "https://k8s.test:6443", "token" => "tok"})
      assert conn.url == "https://k8s.test:6443"
    end

    test "accepts custom namespace" do
      assert {:ok, conn} = ExGoCD.K8s.from_config(%{
        "server" => "https://k8s.test", "token" => "t", "namespace" => "gocd-agents"
      })
      assert conn.namespace == "gocd-agents"
    end
  end

  describe "create_pod/3" do
    setup do
      {:ok, conn} = ExGoCD.K8s.from_config(%{"server" => "https://k8s", "token" => "t"})
      {:ok, conn: conn}
    end

    test "creates a pod and returns the name", %{conn: conn} do
      pod = %{"metadata" => %{"name" => "test-agent"}, "spec" => %{"containers" => []}}
      assert {:ok, "test-agent"} = ExGoCD.K8s.create_pod(conn, pod)
    end
  end

  describe "delete_pod/3" do
    setup do
      {:ok, conn} = ExGoCD.K8s.from_config(%{"server" => "https://k8s", "token" => "t"})
      {:ok, conn: conn}
    end

    test "deletes a pod and returns :ok", %{conn: conn} do
      assert :ok = ExGoCD.K8s.delete_pod(conn, "test-agent")
    end
  end

  describe "list_pods/2" do
    setup do
      {:ok, conn} = ExGoCD.K8s.from_config(%{"server" => "https://k8s", "token" => "t"})
      {:ok, conn: conn}
    end

    test "returns a list of pod info maps", %{conn: conn} do
      assert {:ok, pods} = ExGoCD.K8s.list_pods(conn)
      assert length(pods) == 2
      [p1, p2] = pods
      assert p1.name == "pod-1"
      assert p1.phase == "Running"
      assert p2.name == "pod-2"
      assert p2.phase == "Pending"
    end
  end

  describe "from_kubeconfig/1" do
    test "parses a valid kubeconfig YAML" do
      yaml = """
      apiVersion: v1
      kind: Config
      current-context: test-ctx
      clusters:
      - name: test-cluster
        cluster:
          server: https://k8s.test:6443
      users:
      - name: test-user
        user:
          token: my-secret-token
      contexts:
      - name: test-ctx
        context:
          cluster: test-cluster
          user: test-user
      """

      assert {:ok, conn} = ExGoCD.K8s.from_kubeconfig(yaml)
      assert conn.url == "https://k8s.test:6443"
    end
  end
end
