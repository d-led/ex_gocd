defmodule ExGoCD.K8sTest do
  use ExUnit.Case, async: true

  # Tests the config parsing & connection creation paths.
  # Operation tests (create_pod, etc.) require DynamicHTTPProvider mock
  # and are covered by integration tests with a real k8s/k3s cluster.

  describe "from_config/1" do
    test "creates a conn from server and token" do
      assert {:ok, conn} = ExGoCD.K8s.from_config(%{"server" => "https://k8s.test:6443", "token" => "tok"})
      assert conn.url == "https://k8s.test:6443"
      assert conn.insecure_skip_tls_verify
    end

    test "accepts custom namespace" do
      assert {:ok, conn} = ExGoCD.K8s.from_config(%{
        "server" => "https://k8s.test", "token" => "t", "namespace" => "gocd-agents"
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
end
