# Copyright 2026 ex_gocd
# Simulated agent using HTTP and raw TCP WebSockets to test the server protocol over the network.

defmodule ExGoCD.HTTPTestAgent do
  use GenServer
  require Logger
  import Bitwise

  alias ExGoCD.TestAgent.UUID

  @default_ping_interval 3000
  @host ~c"127.0.0.1"
  @port 4000

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    uuid = opts[:uuid] || UUID.uuid4()
    hostname = opts[:hostname] || "http-test-agent-#{String.slice(uuid, 0, 8)}"
    ping_interval = opts[:ping_interval] || @default_ping_interval
    port = opts[:port] || @port
    host = opts[:host] || @host
    resources = opts[:resources] || []
    environments = opts[:environments] || []

    state = %{
      uuid: uuid,
      hostname: hostname,
      ping_interval: ping_interval,
      port: port,
      host: host,
      resources: resources,
      environments: environments,
      cookie: nil,
      socket: nil,
      handshake_done: false,
      runtime_status: "Idle",
      current_build: nil,
      buffer: <<>>,
      ping_timer: nil
    }

    # Start registration and connection asynchronously
    send(self(), :register_and_connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:register_and_connect, state) do
    case register_agent(state) do
      {:ok, cookie} ->
        Logger.info("[HTTPTestAgent] Registration successful. Cookie: #{cookie}")

        case connect_websocket(state) do
          {:ok, socket} ->
            Logger.info("[HTTPTestAgent] TCP Socket connected. Sending WebSocket handshake...")
            send_handshake(socket, state)

            {:noreply,
             %{state | cookie: cookie, socket: socket, buffer: <<>>, handshake_done: false}}

          {:error, reason} ->
            Logger.error(
              "[HTTPTestAgent] TCP Socket connection failed: #{inspect(reason)}. Retrying in 2s..."
            )

            Process.send_after(self(), :register_and_connect, 2000)
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.error("[HTTPTestAgent] Registration failed: #{inspect(reason)}. Retrying in 2s...")
        Process.send_after(self(), :register_and_connect, 2000)
        {:noreply, state}
    end
  end

  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    if state.handshake_done do
      # Process binary frames
      new_buffer = state.buffer <> data
      {frames, remaining} = parse_frames(new_buffer, [])

      new_state =
        Enum.reduce(frames, state, fn frame, acc ->
          handle_websocket_frame(frame, acc)
        end)

      {:noreply, %{new_state | buffer: remaining}}
    else
      # Expect HTTP 101 Response
      if String.contains?(data, "101 Switching Protocols") do
        Logger.info("[HTTPTestAgent] WebSocket handshake successful!")
        # Find where headers end
        [_headers, body] = String.split(data, "\r\n\r\n", parts: 2)
        # Send Join message
        send_join(socket, state)
        # Start heartbeat ping timer
        ping_timer = schedule_ping(state.ping_interval)
        {:noreply, %{state | handshake_done: true, buffer: body, ping_timer: ping_timer}}
      else
        Logger.error("[HTTPTestAgent] Invalid handshake response: #{data}")
        :gen_tcp.close(socket)
        send(self(), :register_and_connect)
        {:noreply, %{state | socket: nil}}
      end
    end
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.warning("[HTTPTestAgent] WebSocket connection closed by server. Reconnecting in 2s...")
    if state.ping_timer, do: Process.cancel_timer(state.ping_timer)
    Process.send_after(self(), :register_and_connect, 2000)
    {:noreply, %{state | socket: nil, ping_timer: nil, handshake_done: false}}
  end

  def handle_info(:send_ping, state) do
    if state.socket && state.handshake_done do
      send_ping(state.socket, state)
      ping_timer = schedule_ping(state.ping_interval)
      {:noreply, %{state | ping_timer: ping_timer}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:run_simulated_build, build_id, console_url}, state) do
    Logger.info("[HTTPTestAgent] Running simulated build tasks for: #{build_id}")

    # 1. Report Preparing status
    send_report(state.socket, state.uuid, build_id, "Preparing", "Building", nil)
    post_log(console_url, "Preparing build workspace...\n")
    Process.sleep(500)

    # 2. Report Building status
    send_report(state.socket, state.uuid, build_id, "Building", "Building", nil)
    post_log(console_url, "Executing build task: mix test\n")
    Process.sleep(500)
    post_log(console_url, "Build completed successfully.\n")

    # 3. Report Completed status
    send_report(state.socket, state.uuid, build_id, "Completed", "Idle", "Passed")

    Logger.info("[HTTPTestAgent] Finished simulated build: #{build_id}")
    {:noreply, %{state | runtime_status: "Idle", current_build: nil}}
  end

  # Helper Functions

  defp host_to_string({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp host_to_string(host) when is_list(host), do: to_string(host)
  defp host_to_string(host) when is_binary(host), do: host

  defp register_agent(state) do
    # 1. GET Token
    host_str = host_to_string(state.host)
    token_url = "http://#{host_str}:#{state.port}/admin/agent/token?uuid=#{state.uuid}"

    case Req.get(token_url) do
      {:ok, %{status: 200, body: token}} ->
        # 2. POST registration
        reg_url = "http://#{host_str}:#{state.port}/admin/agent"

        ip_addr =
          case host_str do
            "localhost" -> "127.0.0.1"
            other -> other
          end

        form_data = [
          uuid: state.uuid,
          hostname: state.hostname,
          ipAddress: ip_addr,
          location: "./work-http",
          operatingSystem: "Simulated HTTP",
          usablespace: to_string(10 * 1024 * 1024 * 1024),
          token: token,
          supportsBuildCommandProtocol: "true",
          agentAutoRegisterResources: Enum.join(state.resources || [], ","),
          agentAutoRegisterEnvironments: Enum.join(state.environments || [], ",")
        ]

        case Req.post(reg_url, form: form_data) do
          {:ok, %{status: 200}} -> {:ok, token}
          other -> {:error, {:registration_post_failed, other}}
        end

      other ->
        {:error, {:token_request_failed, other}}
    end
  end

  defp connect_websocket(state) do
    host_tcp =
      case state.host do
        s when is_binary(s) -> String.to_charlist(s)
        other -> other
      end

    :gen_tcp.connect(host_tcp, state.port, [:binary, active: true, packet: :raw])
  end

  defp send_handshake(socket, state) do
    host_str = host_to_string(state.host)

    request =
      "GET /agent-websocket/websocket HTTP/1.1\r\n" <>
        "Host: #{host_str}:#{state.port}\r\n" <>
        "Upgrade: websocket\r\n" <>
        "Connection: Upgrade\r\n" <>
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" <>
        "Sec-WebSocket-Version: 13\r\n" <>
        "User-Agent: HTTPTestAgent\r\n\r\n"

    :ok = :gen_tcp.send(socket, request)
  end

  defp send_join(socket, state) do
    msg = %{
      "action" => "join",
      "data" => %{
        "uuid" => state.uuid,
        "cookie" => state.cookie,
        "identifier" => %{
          "uuid" => state.uuid,
          "hostName" => state.hostname,
          "ipAddress" => "127.0.0.1"
        }
      }
    }

    send_json(socket, msg)
  end

  defp send_ping(socket, state) do
    msg = %{
      "action" => "ping",
      "data" => %{
        "uuid" => state.uuid,
        "cookie" => state.cookie,
        "runtimeStatus" => state.runtime_status,
        "location" => "./work-http",
        "usableSpace" => 10 * 1024 * 1024 * 1024,
        "operatingSystemName" => "Simulated HTTP",
        "supportsBuildCommandProtocol" => true,
        "identifier" => %{
          "uuid" => state.uuid,
          "hostName" => state.hostname,
          "ipAddress" => "127.0.0.1"
        }
      }
    }

    send_json(socket, msg)
  end

  defp send_report(socket, uuid, build_id, job_state, runtime_status, result) do
    action =
      case job_state do
        "Completed" -> "reportCompleted"
        "Completing" -> "reportCompleting"
        _ -> "reportCurrentStatus"
      end

    msg = %{
      "action" => action,
      "data" => %{
        "buildId" => build_id,
        "jobState" => job_state,
        "result" => result,
        "agentRuntimeInfo" => %{
          "runtimeStatus" => runtime_status,
          "cookie" => "ex-gocd-demo-cookie",
          "identifier" => %{
            "uuid" => uuid,
            "hostName" => "http-test-agent",
            "ipAddress" => "127.0.0.1"
          }
        }
      }
    }

    send_json(socket, msg)
  end

  defp schedule_ping(interval) do
    Process.send_after(self(), :send_ping, interval)
  end

  defp handle_websocket_frame({:text, payload}, state) do
    case Jason.decode(payload) do
      {:ok, %{"action" => "build", "data" => data}} ->
        build_id = data["buildId"]
        console_url = data["consoleURI"]
        Logger.info("[HTTPTestAgent] Received build assignment for: #{build_id}")

        # Trigger build execution asynchronously
        send(self(), {:run_simulated_build, build_id, console_url})

        %{state | runtime_status: "Building", current_build: build_id}

      {:ok, %{"action" => "cancelBuild", "data" => %{"buildId" => build_id}}} ->
        Logger.warning("[HTTPTestAgent] Received cancelBuild request for: #{build_id}")
        # Transition back to Idle
        %{state | runtime_status: "Idle", current_build: nil}

      {:ok, msg} ->
        # Other actions (e.g. setCookie, phx_reply)
        Logger.debug("[HTTPTestAgent] Unhandled action: #{inspect(msg)}")
        state

      _ ->
        state
    end
  end

  defp handle_websocket_frame(_, state), do: state

  # WebSocket Framing implementation

  defp parse_frames(<<>>, acc), do: {Enum.reverse(acc), <<>>}

  defp parse_frames(buffer, acc) do
    case parse_frame(buffer) do
      {:ok, frame, rest} -> parse_frames(rest, [frame | acc])
      :incomplete -> {Enum.reverse(acc), buffer}
    end
  end

  defp parse_frame(<<129, len, payload::binary-size(len), rest::binary>>) when len <= 125 do
    {:ok, {:text, payload}, rest}
  end

  defp parse_frame(<<129, 126, len::16, payload::binary-size(len), rest::binary>>) do
    {:ok, {:text, payload}, rest}
  end

  defp parse_frame(<<129, 127, len::64, payload::binary-size(len), rest::binary>>) do
    {:ok, {:text, payload}, rest}
  end

  defp parse_frame(<<137, len, payload::binary-size(len), rest::binary>>) when len <= 125 do
    {:ok, {:ping, payload}, rest}
  end

  defp parse_frame(<<136, len, payload::binary-size(len), rest::binary>>) when len <= 125 do
    {:ok, {:close, payload}, rest}
  end

  defp parse_frame(buffer) do
    if byte_size(buffer) < 2 do
      :incomplete
    else
      do_parse_frame(buffer)
    end
  end

  defp do_parse_frame(buffer) do
    <<_, len_byte, _::binary>> = buffer
    len_field = len_byte &&& 0x7F
    needed = frame_needed_bytes(len_field)

    if byte_size(buffer) < needed do
      :incomplete
    else
      actual_len = frame_actual_len(buffer, len_field)

      if byte_size(buffer) >= needed + actual_len do
        header = binary_part(buffer, 0, needed)
        payload = binary_part(buffer, needed, actual_len)
        rest = binary_part(buffer, needed + actual_len, byte_size(buffer) - needed - actual_len)
        opcode = binary_part(header, 0, 1) |> :binary.decode_unsigned()
        {:ok, {opcode, payload}, rest}
      else
        :incomplete
      end
    end
  end

  defp frame_needed_bytes(126), do: 4
  defp frame_needed_bytes(127), do: 10
  defp frame_needed_bytes(_), do: 2

  defp frame_actual_len(buffer, 126) do
    <<_, _, l::16, _::binary>> = buffer
    l
  end

  defp frame_actual_len(buffer, 127) do
    <<_, _, l::64, _::binary>> = buffer
    l
  end

  defp frame_actual_len(_buffer, len_field), do: len_field

  defp send_json(socket, map) do
    payload = Jason.encode!(map)
    send_text_frame(socket, payload)
  end

  defp send_text_frame(socket, payload) do
    payload_bytes = :unicode.characters_to_binary(payload)
    len = byte_size(payload_bytes)
    mask_key = :crypto.strong_rand_bytes(4)
    masked_payload = mask_payload(payload_bytes, mask_key, <<>>)

    header =
      cond do
        len <= 125 ->
          <<129, 128 + len>>

        len <= 65_535 ->
          <<129, 254, len::16>>

        true ->
          <<129, 255, len::64>>
      end

    frame = header <> mask_key <> masked_payload
    :ok = :gen_tcp.send(socket, frame)
  end

  defp mask_payload(<<>>, _, acc), do: acc

  defp mask_payload(<<b::8, rest::binary>>, <<m1, m2, m3, m4>>, acc) do
    mask_payload(rest, <<m2, m3, m4, m1>>, acc <> <<bxor(b, m1)>>)
  end

  defp post_log(console_url, line) do
    ts = DateTime.utc_now() |> Calendar.strftime("%H:%M:%S.000")
    payload = ts <> " " <> line
    _ = Req.post(console_url, body: payload)
  end
end
