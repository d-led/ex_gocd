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

    test "falls back to demo token when not in kubeconfig" do
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
      assert config["token"] == "exgocd-demo-token"
    end

    test "returns error for invalid YAML" do
      assert {:error, :invalid_kubeconfig} = ExGoCD.K8s.extract_k3s_config("not: valid: yaml: [")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_kubeconfig} = ExGoCD.K8s.extract_k3s_config("")
    end
  end
end
