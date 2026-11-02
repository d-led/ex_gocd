defmodule ExGoCD.Docker do
  @moduledoc """
  Docker Engine API client for elastic agent container management.

  Talks to the local Docker daemon via Unix socket. Uses Req for HTTP.
  API version is negotiated via /version.

  ## Resource→Image Mapping

  When a job requests resources (e.g. "java", "python"), the scheduler
  can look up a Docker image specific to that resource via the
  `ResourceImages` map in the elastic agent profile properties.
  Falls back to the profile's default `Image`.
  """

  require Logger

  @doc """
  Checks if Docker daemon is reachable. Returns :ok or {:error, reason}.
  """
  @spec ping(keyword()) :: :ok | {:error, String.t()}
  def ping(opts \\ []) do
    socket = Keyword.get(opts, :docker_socket, default_socket())

    case req_get("/_ping", socket, timeout: 2000) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: code}} -> {:error, "Docker ping returned HTTP #{code}"}
      {:error, reason} -> {:error, "Docker unreachable: #{inspect(reason)}"}
    end
  end

  @doc """
  Creates a container from the given image with env vars, resources, and labels.
  Returns {:ok, container_id} or {:error, reason}.
  """
  @spec create_container(
          image :: String.t(),
          env :: %{String.t() => String.t()},
          opts :: keyword()
        ) :: {:ok, String.t()} | {:error, String.t()}
  def create_container(image, env \\ %{}, opts \\ []) do
    socket = Keyword.get(opts, :docker_socket, default_socket())
    memory = Keyword.get(opts, :memory, "2g")
    cpu = Keyword.get(opts, :cpu, "2.0")
    labels = Keyword.get(opts, :labels, %{})
    network = Keyword.get(opts, :network, "bridge")
    name = Keyword.get(opts, :name, "gocd-elastic-#{random_suffix()}")

    env_list =
      Enum.map(env, fn {k, v} -> "#{k}=#{v}" end)

    body = %{
      Image: image,
      Env: env_list,
      HostConfig: %{
        Memory: parse_memory(memory),
        NanoCPUs: parse_nano_cpus(cpu),
        NetworkMode: network,
        AutoRemove: true
      },
      Labels: Map.merge(%{"app" => "gocd-elastic-agent"}, labels)
    }

    query = "?name=#{URI.encode(name)}"

    case req_post("/containers/create#{query}", socket, body) do
      {:ok, %{status: 201, body: %{"Id" => container_id}}} ->
        {:ok, container_id}

      {:ok, %{status: code, body: body}} ->
        error = body |> Map.get("message", "HTTP #{code}") |> String.slice(0, 200)
        {:error, error}

      {:error, reason} ->
        {:error, "Docker create failed: #{inspect(reason)}"}
    end
  end

  @doc "Starts a container. Returns :ok or {:error, reason}."
  def start_container(container_id, opts \\ []) do
    socket = Keyword.get(opts, :docker_socket, default_socket())

    case req_post("/containers/#{container_id}/start", socket, %{}) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: 304} = _resp} ->
        Logger.debug("[Docker] Container #{String.slice(container_id, 0, 12)} already started")
        :ok

      {:ok, %{status: code, body: body}} ->
        error = body |> Map.get("message", "HTTP #{code}") |> String.slice(0, 200)
        {:error, error}

      {:error, reason} ->
        {:error, "Docker start failed: #{inspect(reason)}"}
    end
  end

  @doc "Stops a container. Returns :ok or {:error, reason}."
  def stop_container(container_id, opts \\ []) do
    socket = Keyword.get(opts, :docker_socket, default_socket())

    case req_post("/containers/#{container_id}/stop", socket, %{}) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: 304} = _resp} ->
        Logger.debug("[Docker] Container #{String.slice(container_id, 0, 12)} already stopped")
        :ok

      {:ok, %{status: code, body: body}} ->
        error = body |> Map.get("message", "HTTP #{code}") |> String.slice(0, 200)
        {:error, error}

      {:error, reason} ->
        {:error, "Docker stop failed: #{inspect(reason)}"}
    end
  end

  @doc "Removes a container (force if running). Returns :ok or {:error, reason}."
  def remove_container(container_id, opts \\ []) do
    socket = Keyword.get(opts, :docker_socket, default_socket())

    case req_delete("/containers/#{container_id}?force=true", socket) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: code, body: body}} ->
        error = body |> Map.get("message", "HTTP #{code}") |> String.slice(0, 200)
        {:error, error}

      {:error, reason} ->
        {:error, "Docker remove failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Lists containers matching labels. Returns list of container maps or {:error, reason}.
  """
  def list_containers(labels \\ %{}, opts \\ []) do
    socket = Keyword.get(opts, :docker_socket, default_socket())
    label_filter = Enum.map_join(labels, ",", fn {k, v} -> "#{k}=#{v}" end)
    filters = %{label: [label_filter]} |> Jason.encode!()
    query = if label_filter != "", do: "?filters=#{URI.encode(filters)}", else: ""

    case req_get("/containers/json#{query}", socket) do
      {:ok, %{status: 200, body: containers}} ->
        {:ok, containers}

      {:ok, %{status: code}} ->
        {:error, "Docker list failed: HTTP #{code}"}

      {:error, reason} ->
        {:error, "Docker list failed: #{inspect(reason)}"}
    end
  end

  @doc "Lists all containers. Returns list of container maps or {:error, reason}."
  def list_all_containers(opts \\ []) do
    socket = Keyword.get(opts, :docker_socket, default_socket())

    case req_get("/containers/json?all=true", socket) do
      {:ok, %{status: 200, body: containers}} ->
        {:ok, containers}

      {:ok, %{status: code}} ->
        {:error, "Docker list failed: HTTP #{code}"}

      {:error, reason} ->
        {:error, "Docker list failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Returns the default Docker socket path for the current OS.
  """
  def default_socket do
    System.get_env("DOCKER_HOST") || System.get_env("DOCKER_SOCKET") || platform_socket()
  end

  # Where a daemon listens when nothing said otherwise. Docker Desktop on macOS
  # keeps its socket under the user's home; everywhere else it is the system one.
  defp platform_socket do
    case :os.type() do
      {:unix, :darwin} -> "#{System.get_env("HOME") || "/tmp"}/.docker/run/docker.sock"
      _ -> "/var/run/docker.sock"
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp req_get(path, socket, opts \\ []) do
    url = "http://localhost#{path}"
    timeout = Keyword.get(opts, :timeout, 5000)

    Req.get(url,
      unix_socket: socket,
      receive_timeout: timeout,
      connect_options: [timeout: timeout],
      retry: false
    )
    |> handle_resp()
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp req_post(path, socket, body) do
    url = "http://localhost#{path}"

    Req.post(url,
      unix_socket: socket,
      json: body,
      receive_timeout: 10_000,
      connect_options: [timeout: 5000],
      retry: false
    )
    |> handle_resp()
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp req_delete(path, socket) do
    url = "http://localhost#{path}"

    Req.delete(url,
      unix_socket: socket,
      receive_timeout: 10_000,
      connect_options: [timeout: 5000],
      retry: false
    )
    |> handle_resp()
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp handle_resp({:ok, %Req.Response{status: status, body: body}}) do
    {:ok, %{status: status, body: decode_body(body)}}
  end

  defp handle_resp({:error, error}), do: {:error, error}

  # Docker answers JSON, except when it does not (an empty body on 204, a plain
  # error string); a body that is not JSON is passed on as it came.
  defp decode_body(body) when is_binary(body) and body != "" do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> body
    end
  end

  defp decode_body(body), do: body

  defp random_suffix, do: 8 |> :crypto.strong_rand_bytes() |> Base.hex_encode32(case: :lower)

  # Docker wants bytes and nanocpus; a profile says "4Gi" and "2". The suffix picks
  # the multiplier, and a value the app cannot read falls back to the profile
  # default rather than sending zero.
  @default_memory 2_147_483_648
  @default_nano_cpus 2_000_000_000

  @memory_multipliers %{
    "k" => 1_024,
    "m" => 1_024 * 1_024,
    "g" => 1_024 * 1_024 * 1_024,
    "t" => 1_024 * 1_024 * 1_024 * 1_024
  }

  defp parse_memory(mem) when is_binary(mem) do
    case parse_quantity(mem) do
      {value, multiplier} -> round(value * multiplier)
      :error -> @default_memory
    end
  end

  defp parse_memory(_int), do: @default_memory

  defp parse_nano_cpus(cpu) when is_binary(cpu) do
    case parse_quantity(cpu) do
      {value, multiplier} -> round(value * multiplier * 1_000_000_000)
      :error -> @default_nano_cpus
    end
  end

  defp parse_nano_cpus(cpu) when is_number(cpu), do: round(cpu * 1_000_000_000)
  defp parse_nano_cpus(_), do: @default_nano_cpus

  # "4Gi", "512Mb", "2" → the number and what a unit is worth. The unit is whatever
  # follows the number, with the "i" or "B" people write after it taken off, since
  # "3Gi", "3G" and "3GB" are the same amount of memory.
  defp parse_quantity(quantity) do
    with [_, digits, suffix] <- Regex.run(~r/\A([0-9]+(?:\.[0-9]+)?)(.*)\z/s, quantity),
         {value, ""} <- Float.parse(digits) do
      {value, Map.get(@memory_multipliers, normalize_unit(suffix), 1)}
    else
      _ -> :error
    end
  end

  defp normalize_unit(suffix) do
    suffix |> String.downcase() |> String.trim_trailing("b") |> String.trim_trailing("i")
  end
end
