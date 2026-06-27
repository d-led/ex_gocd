defmodule ExGoCD.K8s do
  @moduledoc """
  Thin Kubernetes API client for pod management.

  Configured from cluster profile properties (server URL, namespace, token, CA cert).
  Accepts either a kubeconfig YAML string or individual fields. No specific k8s
  distribution is assumed — bring your own cluster.

  ## Design

  Mirrors `KubernetesClientFactory` from GoCD's `kubernetes-elastic-agents` plugin:
  - Stateless HTTP client — one per cluster profile UUID
  - Bearer token auth with optional CA cert
  - Pod CRUD only (create/delete/list)
  - No scheduling logic (see ElasticAgentScheduler)
  """

  @type t :: %{
          server: String.t(),
          token: String.t(),
          ca_cert: String.t() | nil,
          namespace: String.t()
        }

  # ── Construction ──────────────────────────────────────────────────────

  @doc """
  Creates a client from individual cluster profile fields.

  Accepts: server (required), token (required), ca_cert (optional PEM),
  namespace (defaults to "default").
  """
  def new(server, token, opts \\ []) do
    {:ok,
     %{
       server: String.trim_trailing(server, "/"),
       token: token,
       ca_cert: Keyword.get(opts, :ca_cert),
       namespace: Keyword.get(opts, :namespace, "default")
     }}
  end

  @doc """
  Creates a client from a kubeconfig YAML string (e.g. copy-pasted from ~/.kube/config).

  Parses the current-context's cluster server, user token, and CA certificate.
  """
  def from_kubeconfig(yaml_string, opts \\ []) do
    with {:ok, config} <- parse_config(yaml_string),
         {:ok, server} <- extract_server(config),
         {:ok, token} <- extract_token(config) do
      ca = extract_ca(config)
      ns = Keyword.get(opts, :namespace) || extract_namespace(config) || "default"
      {:ok, %{server: String.trim_trailing(server, "/"), token: token, ca_cert: ca, namespace: ns}}
    end
  end

  defp parse_config(""), do: {:error, "Empty kubeconfig"}
  defp parse_config(string), do: YamlElixir.read_from_string(string)

  # ── Pod operations ────────────────────────────────────────────────────

  @doc "Creates a Pod. Returns {:ok, pod_name} or {:error, reason}."
  @spec create_pod(t(), map()) :: {:ok, String.t()} | {:error, term()}
  def create_pod(client, pod_spec) do
    name = get_in(pod_spec, ["metadata", "name"]) || "gocd-agent-#{random_suffix()}"
    url = pod_url(client)

    case post(client, url, pod_spec) do
      {:ok, %{status: s}} when s in 200..202 -> {:ok, name}
      {:ok, %{status: 409}} -> {:ok, name}
      {:ok, resp} -> {:error, "k8s API returned #{resp.status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Deletes a Pod by name."
  @spec delete_pod(t(), String.t()) :: :ok | {:error, term()}
  def delete_pod(client, pod_name) do
    url = "#{pod_url(client)}/#{pod_name}"

    case delete(client, url) do
      {:ok, %{status: s}} when s in 200..202 -> :ok
      {:ok, %{status: 404}} -> :ok
      {:ok, resp} -> {:error, "k8s API returned #{resp.status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Lists pods matching an optional label selector."
  @spec list_pods(t(), String.t() | nil) :: {:ok, list(map())} | {:error, term()}
  def list_pods(client, label_selector \\ nil) do
    url = pod_url(client)
    url = if label_selector, do: "#{url}?labelSelector=#{URI.encode_www_form(label_selector)}", else: url

    case get(client, url) do
      {:ok, %{status: 200, body: body}} ->
        items = get_in(body, ["items"]) || []
        {:ok, Enum.map(items, &extract_pod_info/1)}

      {:error, reason} -> {:error, reason}
    end
  end

  # ── kubeconfig parsing ────────────────────────────────────────────────

  defp extract_server(config) do
    with ctx <- current_context(config),
         cluster_name when is_binary(cluster_name) <- get_in(ctx, ["context", "cluster"]),
         cluster when is_map(cluster) <- find_by_name(config["clusters"] || [], cluster_name),
         server when is_binary(server) <- get_in(cluster, ["cluster", "server"]) do
      {:ok, server}
    else
      _ -> {:error, "Could not find cluster server in kubeconfig"}
    end
  end

  defp extract_token(config) do
    with ctx <- current_context(config),
         user_name when is_binary(user_name) <- get_in(ctx, ["context", "user"]),
         user when is_map(user) <- find_by_name(config["users"] || [], user_name),
         token when is_binary(token) <- get_in(user, ["user", "token"]) || get_in(user, ["user", "client-certificate-data"]) do
      {:ok, token}
    else
      _ -> {:error, "Could not find user token in kubeconfig"}
    end
  end

  defp extract_ca(config) do
    with ctx <- current_context(config),
         cluster_name <- get_in(ctx, ["context", "cluster"]),
         cluster <- find_by_name(config["clusters"] || [], cluster_name) do
      get_in(cluster, ["cluster", "certificate-authority-data"])
    end
  end

  defp extract_namespace(config) do
    get_in(current_context(config), ["context", "namespace"])
  end

  defp current_context(config) do
    current = config["current-context"]
    find_by_name(config["contexts"] || [], current)
  end

  defp find_by_name(items, name) do
    Enum.find(items || [], fn item -> item["name"] == name end)
  end

  # ── HTTP (Req) ────────────────────────────────────────────────────────

  defp pod_url(client),
    do: "#{client.server}/api/v1/namespaces/#{client.namespace}/pods"

  defp get(client, url) do
    Req.get(url, headers: auth_headers(client), connect_options: tls_opts(client))
  end

  defp post(client, url, body) do
    Req.post(url, json: body, headers: auth_headers(client), connect_options: tls_opts(client))
  end

  defp delete(client, url) do
    Req.delete(url, headers: auth_headers(client), connect_options: tls_opts(client))
  end

  defp auth_headers(client) do
    [{"Authorization", "Bearer #{client.token}"}]
  end

  defp tls_opts(%{ca_cert: nil}) do
    [transport_opts: [verify: :verify_none]]
  end

  defp tls_opts(%{ca_cert: pem}) do
    decoded =
      case Base.decode64(pem) do
        {:ok, data} -> data
        :error -> pem
      end

    cert_path = Path.join(System.tmp_dir!(), "ex_gocd_k8s_ca_#{random_suffix()}.pem")
    File.write!(cert_path, decoded)
    [transport_opts: [cacertfile: cert_path]]
  end

  # ── helpers ───────────────────────────────────────────────────────────

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
