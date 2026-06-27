defmodule ExGoCD.K8s do
  @moduledoc """
  Kubernetes API client for elastic agent pod management.
  Thin wrapper around the `k8s` Elixir package (2M+ downloads).

  ## Module name note

  This module is `ExGoCD.K8s` which shadows the `K8s` hex package.
  We use `:\"Elixir.K8s\"` atom syntax for the hex package references.
  """

  # k8s hex package references — atom syntax avoids ExGoCD.K8s shadowing
  @k8s_conn :"Elixir.K8s.Conn"
  @k8s_client :"Elixir.K8s.Client"

  @type conn :: K8s.Conn.t()

  @doc "Creates a connection from a kubeconfig YAML string."
  @spec from_kubeconfig(String.t()) :: {:ok, conn()} | {:error, term()}
  def from_kubeconfig(yaml_string) do
    @k8s_conn.from_string(yaml_string)
  end

  @doc "Creates a connection from explicit cluster profile fields."
  @spec from_config(map()) :: {:ok, conn()} | {:error, term()}
  def from_config(%{"server" => server, "token" => token} = config) do
    ca_line = if config["ca_cert"], do: "    certificate-authority-data: #{config["ca_cert"]}", else: "    insecure-skip-tls-verify: true"
    ns = config["namespace"] || "default"
    yaml = "apiVersion: v1\nkind: Config\ncurrent-context: default\n" <>
           "clusters:\n- name: default\n  cluster:\n    server: #{server}\n#{ca_line}\n" <>
           "users:\n- name: default\n  user:\n    token: #{token}\n" <>
           "contexts:\n- name: default\n  context:\n    cluster: default\n    user: default\n    namespace: #{ns}\n"
    @k8s_conn.from_string(yaml)
  end

  @doc "Creates a Pod. Returns {:ok, pod_name} or {:error, reason}."
  @spec create_pod(conn(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def create_pod(conn, pod_spec, opts \\ []) do
    ns = Keyword.get(opts, :namespace, "default")
    name = get_in(pod_spec, ["metadata", "name"]) || "gocd-agent-#{random_suffix()}"

    resource = Map.merge(pod_spec, %{"apiVersion" => "v1", "kind" => "Pod"})
    resource = put_in(resource, ["metadata", "namespace"], ns)

    operation = @k8s_client.create(resource)

    case @k8s_client.run(conn, operation) do
      {:ok, _} -> {:ok, name}
      {:error, %{reason: :already_exists}} -> {:ok, name}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Deletes a Pod by name."
  @spec delete_pod(conn(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_pod(conn, pod_name, opts \\ []) do
    ns = Keyword.get(opts, :namespace, "default")
    operation = @k8s_client.delete("v1", "Pod", namespace: ns, name: pod_name)

    case @k8s_client.run(conn, operation) do
      {:ok, _} -> :ok
      {:error, %{reason: :not_found}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Lists pods matching an optional label selector."
  @spec list_pods(conn(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_pods(conn, opts \\ []) do
    ns = Keyword.get(opts, :namespace, "default")
    label = Keyword.get(opts, :label_selector)

    path_params = [namespace: ns]
    path_params = if label, do: Keyword.put(path_params, :labelSelector, label), else: path_params

    operation = @k8s_client.list("v1", "Pod", path_params)

    case @k8s_client.run(conn, operation) do
      {:ok, result} ->
        items = get_in(result, ["items"]) || []
        {:ok, Enum.map(items, &extract_pod_info/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_pod_info(item) do
    %{
      name: get_in(item, ["metadata", "name"]),
      phase: get_in(item, ["status", "phase"]),
      host_ip: get_in(item, ["status", "hostIP"]),
      labels: get_in(item, ["metadata", "labels"]) || %{}
    }
  end

  defp random_suffix, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
