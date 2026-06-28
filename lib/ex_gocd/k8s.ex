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
  def from_config(%{"server" => server} = config) do
    ca_line =
      if config["ca_cert"],
        do: "    certificate-authority-data: #{config["ca_cert"]}",
        else: "    insecure-skip-tls-verify: true"

    user_block =
      cond do
        config["client_cert"] && config["client_key"] ->
          "    client-certificate-data: #{config["client_cert"]}\n    client-key-data: #{config["client_key"]}"

        config["token"] ->
          "    token: #{config["token"]}"

        true ->
          "    token: unused"
      end

    ns = config["namespace"] || "default"

    yaml =
      "apiVersion: v1\nkind: Config\ncurrent-context: default\n" <>
        "clusters:\n- name: default\n  cluster:\n    server: #{server}\n#{ca_line}\n" <>
        "users:\n- name: default\n  user:\n#{user_block}\n" <>
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

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Tests connectivity to a Kubernetes cluster by querying the API.

  Lists pods (limit 1) via the k8s API. Runs in a linked process that
  is brutally killed (:kill) after 2 seconds — unlike Task.shutdown,
  Process.exit(:kill) can interrupt blocking NIF calls.

  Returns `:ok` on success, or `{:error, reason}` where reason is
  a human-readable string for UI display.
  """
  @spec ping(conn(), keyword()) :: :ok | {:error, String.t()}
  def ping(conn, opts \\ []) do
    ns = Keyword.get(opts, :namespace, "default")
    parent = self()

    task =
      Task.async(fn ->
        path_params = [namespace: ns, limit: 1]
        operation = @k8s_client.list("v1", "Pod", path_params)
        result = @k8s_client.run(conn, operation)
        send(parent, {:ping_result, result})
      end)

    receive do
      {:ping_result, {:ok, _}} ->
        :ok

      {:ping_result, {:error, error}} ->
        {:error, format_error(error)}
    after
      2000 ->
        Process.exit(task.pid, :kill)
        {:error, "Timed out — cluster unreachable"}
    end
  end

  @doc false
  def format_error(%{reason: :unauthorized}), do: "Unauthorized — invalid token"
  def format_error(%{reason: :forbidden}), do: "Forbidden — token lacks permissions"
  def format_error(%{reason: :connect_timeout}), do: "Connection timed out — unreachable"
  def format_error(%{reason: :nxdomain}), do: "DNS resolution failed — check server URL"
  def format_error(%{reason: :econnrefused}), do: "Connection refused — cluster running?"
  def format_error(%{reason: :ssl_error}), do: "TLS error — check CA certificate"
  def format_error(%{reason: :not_found}), do: "Connected — namespace not found"

  # HTTP response with status code embedded (k8s client wraps these)
  def format_error(%{status: 401}), do: "Unauthorized — verify bearer token"
  def format_error(%{status: 403}), do: "Forbidden — insufficient RBAC permissions"
  def format_error(%{status: code}) when is_integer(code), do: "HTTP #{code}"

  def format_error(%{message: msg}) when is_binary(msg), do: msg
  def format_error(other), do: "Error: #{inspect(other)}"

  @doc """
  Discover a local k3s cluster for development.

  Tries, in order:
  1. Read kubeconfig from `/tmp/k3s-kubeconfig/kubeconfig.yaml` (docker-compose k3s)
  2. Fall back to `k3s kubectl config view` CLI

  Returns `{:ok, config_map}` with keys: `"server"`, `"token"`, `"ca_cert"`, `"namespace"`
  or `{:error, :not_found}` when no local k3s is available.
  """
  @spec discover_local_k3s() :: {:ok, map()} | {:error, :not_found | term()}
  def discover_local_k3s do
    kubeconfig_paths()
    |> Enum.find_value(&try_kubeconfig_file/1)
    |> case do
      {:ok, _} = result -> result
      nil -> try_k3s_cli()
    end
  end

  defp kubeconfig_paths do
    # Only check k3s-specific paths, not arbitrary kubeconfig files.
    # In dev, docker-compose k3s writes to /tmp/k3s-kubeconfig/kubeconfig.yaml.
    # Fall back to KUBECONFIG env if explicitly set for k3s.
    [
      "/tmp/k3s-kubeconfig/kubeconfig.yaml",
      System.get_env("KUBECONFIG")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp try_kubeconfig_file(path) do
    with true <- File.exists?(path),
         {:ok, yaml} <- File.read(path),
         {:ok, config} <- extract_k3s_config(yaml) do
      {:ok, config}
    else
      _ -> nil
    end
  end

  defp try_k3s_cli do
    case System.find_executable("k3s") do
      nil ->
        {:error, :not_found}

      k3s_path ->
        {output, 0} = System.cmd(k3s_path, ["kubectl", "config", "view", "--raw"])
        extract_k3s_config(output)
    end
  rescue
    _ -> {:error, :not_found}
  end

  @doc false
  def extract_k3s_config(yaml) do
    with {:ok, parsed} <- YamlElixir.read_from_string(yaml),
         [%{"clusters" => [%{"cluster" => cluster} | _]} | _] <- [parsed],
         server <- cluster["server"] do
      ca_cert = cluster["certificate-authority-data"]

      {token, client_cert, client_key} =
        case parsed do
          %{"users" => [%{"user" => user} | _]} ->
            {Map.get(user, "token"), Map.get(user, "client-certificate-data"),
             Map.get(user, "client-key-data")}

          _ ->
            {"exgocd-demo-token", nil, nil}
        end

      namespace =
        case parsed do
          %{"contexts" => [%{"context" => %{"namespace" => ns}} | _]} -> ns
          _ -> "default"
        end

      # Rewrite docker internal hostname/k3s hostname to localhost for host access
      local_server =
        server
        |> String.replace(~r{https?://k3s:}, "https://localhost:")
        |> String.replace(~r{https?://host\.docker\.internal:}, "https://localhost:")

      {:ok,
       %{
         "server" => local_server,
         "token" => token,
         "ca_cert" => ca_cert,
         "namespace" => namespace,
         "client_cert" => client_cert,
         "client_key" => client_key
       }}
    else
      _ -> {:error, :invalid_kubeconfig}
    end
  end

  defp extract_pod_info(item) do
    created = get_in(item, ["metadata", "creationTimestamp"])

    created_at =
      case created do
        ts when is_binary(ts) ->
          case DateTime.from_iso8601(ts) do
            {:ok, dt, _} -> dt
            _ -> nil
          end

        _ ->
          nil
      end

    %{
      name: get_in(item, ["metadata", "name"]),
      phase: get_in(item, ["status", "phase"]),
      host_ip: get_in(item, ["status", "hostIP"]),
      labels: get_in(item, ["metadata", "labels"]) || %{},
      created_at: created_at
    }
  end

  defp random_suffix, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
