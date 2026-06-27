defmodule ExGoCD.K8sTest do
  use ExUnit.Case, async: true
  alias ExGoCD.K8s

  describe "new/3" do
    test "creates a client from cluster profile fields" do
      assert {:ok, client} = K8s.new("https://k8s.example.com:6443", "token-123", namespace: "gocd")

      assert client.server == "https://k8s.example.com:6443"
      assert client.token == "token-123"
      assert client.namespace == "gocd"
      assert client.ca_cert == nil
    end

    test "strips trailing slash from server URL" do
      {:ok, client} = K8s.new("https://k8s:6443/", "t")
      assert client.server == "https://k8s:6443"
    end

    test "defaults namespace to default" do
      {:ok, client} = K8s.new("https://k8s", "t")
      assert client.namespace == "default"
    end

    test "stores CA cert when provided" do
      {:ok, client} = K8s.new("https://k8s", "t", ca_cert: "PEM-DATA")
      assert client.ca_cert == "PEM-DATA"
    end
  end

  describe "from_kubeconfig/2" do
    test "parses a valid kubeconfig YAML string" do
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
          namespace: gocd-agents
      """

      assert {:ok, client} = K8s.from_kubeconfig(yaml)
      assert client.server == "https://k8s.test:6443"
      assert client.token == "my-secret-token"
      assert client.namespace == "gocd-agents"
    end

    test "parses CA cert from certificate-authority-data" do
      yaml = """
      current-context: ctx
      clusters:
      - name: c
        cluster:
          server: https://k8s
          certificate-authority-data: Q0EtQ0VSVA==
      users:
      - name: u
        user:
          token: t
      contexts:
      - name: ctx
        context:
          cluster: c
          user: u
      """

      assert {:ok, client} = K8s.from_kubeconfig(yaml)
      assert client.ca_cert == "Q0EtQ0VSVA=="
    end

    test "allows overriding namespace" do
      yaml = """
      current-context: ctx
      clusters:
      - name: c
        cluster:
          server: https://k8s
      users:
      - name: u
        user:
          token: t
      contexts:
      - name: ctx
        context:
          cluster: c
          user: u
          namespace: original
      """

      assert {:ok, client} = K8s.from_kubeconfig(yaml, namespace: "override")
      assert client.namespace == "override"
    end

    test "returns error when kubeconfig has no server" do
      yaml = """
      current-context: ctx
      clusters: []
      users: [{name: u, user: {token: t}}]
      contexts: [{name: ctx, context: {cluster: c, user: u}}]
      """

      assert {:error, msg} = K8s.from_kubeconfig(yaml)
      assert msg =~ "server"
    end

    test "returns error for empty YAML string" do
      assert {:error, _} = K8s.from_kubeconfig("")
    end
  end

  describe "pod operations against unreachable cluster" do
    setup do
      {:ok, client} = K8s.new("https://k8s.invalid:6443", "token")
      {:ok, client: client}
    end

    test "create_pod/2 returns error", %{client: client} do
      assert {:error, _} = K8s.create_pod(client, %{
        "metadata" => %{"name" => "test-pod"},
        "spec" => %{"containers" => [%{"name" => "test", "image" => "alpine"}]}
      })
    end

    test "delete_pod/2 returns error", %{client: client} do
      assert {:error, _} = K8s.delete_pod(client, "test-pod")
    end

    test "list_pods/1 returns error", %{client: client} do
      assert {:error, _} = K8s.list_pods(client)
    end
  end
end
