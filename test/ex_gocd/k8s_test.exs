defmodule ExGoCD.K8sTest do
  use ExUnit.Case, async: true

  # Tests the config parsing & connection creation paths.
  # Operation tests (create_pod, etc.) require DynamicHTTPProvider mock
  # and are covered by integration tests with a real k8s/k3s cluster.

  describe "from_config/1" do
    test "creates a conn from server and token" do
      assert {:ok, conn} =
               ExGoCD.K8s.from_config(%{"server" => "https://k8s.test:6443", "token" => "tok"})

      assert conn.url == "https://k8s.test:6443"
      assert conn.insecure_skip_tls_verify
    end

    test "accepts custom namespace" do
      assert {:ok, conn} =
               ExGoCD.K8s.from_config(%{
                 "server" => "https://k8s.test",
                 "token" => "t",
                 "namespace" => "gocd-agents"
               })

      assert conn.url == "https://k8s.test"
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
          insecure-skip-tls-verify: true
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

    test "returns error for empty string" do
      assert {:error, _} = ExGoCD.K8s.from_kubeconfig("")
    end
  end

  describe "extract_k3s_config/1" do
    test "parses a valid k3s-style kubeconfig YAML" do
      yaml = """
      apiVersion: v1
      kind: Config
      current-context: default
      clusters:
      - name: default
        cluster:
          server: https://k3s:6443
          certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCmZha2UtY2EKLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
      users:
      - name: default
        user:
          token: my-k3s-token
      contexts:
      - name: default
        context:
          cluster: default
          user: default
          namespace: gocd-agents
      """

      assert {:ok, config} = ExGoCD.K8s.extract_k3s_config(yaml)
      assert config["server"] == "https://localhost:6443"
      assert config["token"] == "my-k3s-token"

      assert config["ca_cert"] ==
               "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCmZha2UtY2EKLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo="

      assert config["namespace"] == "gocd-agents"
    end

    test "rewrites host.docker.internal to localhost" do
      yaml = """
      apiVersion: v1
      kind: Config
      clusters:
      - cluster:
          server: https://host.docker.internal:6443
      users:
      - user:
          token: t
      """

      assert {:ok, config} = ExGoCD.K8s.extract_k3s_config(yaml)
      assert config["server"] == "https://localhost:6443"
    end

    test "preserves localhost URLs unchanged" do
      yaml = """
      apiVersion: v1
      kind: Config
      clusters:
      - cluster:
          server: https://localhost:6443
      users:
      - user:
          token: t
      """

      assert {:ok, config} = ExGoCD.K8s.extract_k3s_config(yaml)
      assert config["server"] == "https://localhost:6443"
    end

    test "falls back to default namespace when not specified" do
      yaml = """
      apiVersion: v1
      kind: Config
      clusters:
      - cluster:
          server: https://k3s:6443
      users:
      - user:
          token: t
      contexts:
      - context:
          cluster: default
          user: default
      """

      assert {:ok, config} = ExGoCD.K8s.extract_k3s_config(yaml)
      assert config["namespace"] == "default"
    end

    test "returns client cert/key when present, no fallback token" do
      yaml = """
      apiVersion: v1
      kind: Config
      clusters:
      - cluster:
          server: https://k3s:6443
      users:
      - user:
          client-certificate-data: ZmFrZQ==
          client-key-data: ZmFrZQ==
      """

      assert {:ok, config} = ExGoCD.K8s.extract_k3s_config(yaml)
      assert config["token"] == nil
      assert config["client_cert"] == "ZmFrZQ=="
      assert config["client_key"] == "ZmFrZQ=="
    end

    test "returns error for invalid YAML" do
      assert {:error, :invalid_kubeconfig} = ExGoCD.K8s.extract_k3s_config("not: valid: yaml: [")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_kubeconfig} = ExGoCD.K8s.extract_k3s_config("")
    end
  end

  # Both of these ask Kubernetes for a state that may already hold. A pod that
  # exists is what create_pod wanted; a pod that is gone is what delete_pod
  # wanted. Kubernetes reports both as a reason string, not an atom.
  describe "asking for a state that already holds" do
    setup do
      provider = K8s.Client.DynamicHTTPProvider
      start_supervised!(provider)

      {:ok, conn} =
        ExGoCD.K8s.from_config(%{"server" => "https://k8s.test:6443", "token" => "tok"})

      # The conn's default provider is baked in when the k8s library is compiled,
      # so the fake has to be handed to this conn rather than configured.
      %{conn: %{conn | http_provider: provider}}
    end

    test "a pod that already exists counts as created", %{conn: conn} do
      refuse_with("AlreadyExists", "pods \"gocd-agent-1\" already exists")

      assert {:ok, "gocd-agent-1"} =
               ExGoCD.K8s.create_pod(conn, %{"metadata" => %{"name" => "gocd-agent-1"}})
    end

    test "a pod that is already gone counts as deleted", %{conn: conn} do
      refuse_with("NotFound", "pods \"gocd-agent-1\" not found")

      assert :ok = ExGoCD.K8s.delete_pod(conn, "gocd-agent-1")
    end

    test "anything else is still a failure", %{conn: conn} do
      refuse_with("Forbidden", "pods is forbidden")

      assert {:error, %{reason: "Forbidden"}} =
               ExGoCD.K8s.create_pod(conn, %{"metadata" => %{"name" => "gocd-agent-1"}})
    end
  end

  defp refuse_with(reason, message) do
    K8s.Client.DynamicHTTPProvider.register(self(), fn _method, _uri, _body, _headers, _opts ->
      {:error, %K8s.Client.APIError{reason: reason, message: message}}
    end)
  end
end
