# Copyright 2026 ex_gocd
# Simulated agent using HTTP and raw TCP WebSockets to test the server protocol over the network.

defmodule ExGoCD.HTTPTestAgent do
  use GenServer
  require Logger
  import Bitwise

  alias ExGoCD.Agents
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
  def terminate(_reason, state) do
    # Deregister from DB so the agent doesn’t linger after cleanup.
    case Agents.get_agent_by_uuid(state.uuid) do
      nil ->
        :ok

      agent ->
        _ = Agents.disable_agent(agent)
        _ = Agents.delete_agent(agent)
    end

    if state.socket, do: :gen_tcp.close(state.socket)
    :ok
  end

  @impl true
  def handle_info(:register_and_connect, state), do: connect(state)

  def handle_info({:tcp, socket, data}, %{socket: socket} = state),
    do: receive_data(socket, data, state)

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state),
    do: connection_closed(socket, state)

  def handle_info(:send_ping, state), do: heartbeat(state)

  def handle_info({:run_simulated_build, build_id, console_url}, state),
    do: run_simulated_build(build_id, console_url, state)

  # ── What an incoming message means ─────────────────────────────────────────

  defp connect(state) do
    case register_agent(state) do
      {:ok, cookie} -> established(state, cookie)
      {:error, reason} -> retry(state, "Registration failed", reason)
    end
  end

  defp established(state, cookie) do
    Logger.info("[HTTPTestAgent] Registration successful. Cookie: #{cookie}")

    case connect_websocket(state) do
      {:ok, socket} -> handshake_started(state, cookie, socket)
      {:error, reason} -> retry(state, "TCP Socket connection failed", reason)
    end
  end

  defp handshake_started(state, cookie, socket) do
    Logger.info("[HTTPTestAgent] TCP Socket connected. Sending WebSocket handshake...")
    send_handshake(socket, state)

    {:noreply, %{state | cookie: cookie, socket: socket, buffer: <<>>, handshake_done: false}}
  end

  defp retry(state, what, reason) do
    Logger.error("[HTTPTestAgent] #{what}: #{inspect(reason)}. Retrying in 2s...")
    Process.send_after(self(), :register_and_connect, 2000)
    {:noreply, state}
  end

  # The socket answers the handshake once; after that everything is frames.
  defp receive_data(_socket, data, %{handshake_done: true} = state), do: frame_data(data, state)
  defp receive_data(socket, data, state), do: handshake_response(socket, data, state)

  defp frame_data(data, state) do
    {frames, remaining} = parse_frames(state.buffer <> data, [])

    new_state =
      Enum.reduce(frames, state, fn frame, acc -> handle_websocket_frame(frame, acc) end)

    {:noreply, %{new_state | buffer: remaining}}
  end

  defp handshake_response(socket, data, state) do
    if String.contains?(data, "101 Switching Protocols") do
      handshake_accepted(socket, data, state)
    else
      handshake_refused(socket, data, state)
    end
  end

  defp handshake_accepted(socket, data, state) do
    Logger.info("[HTTPTestAgent] WebSocket handshake successful!")

    [_headers, body] = String.split(data, "\r\n\r\n", parts: 2)
    send_join(socket, state)
    ping_timer = schedule_ping(state.ping_interval)

    {:noreply, %{state | handshake_done: true, buffer: body, ping_timer: ping_timer}}
  end

  defp handshake_refused(socket, data, state) do
    Logger.error("[HTTPTestAgent] Invalid handshake response: #{data}")
    :gen_tcp.close(socket)
    send(self(), :register_and_connect)
    {:noreply, %{state | socket: nil}}
  end

  defp connection_closed(_closed_socket, state) do
    Logger.warning("[HTTPTestAgent] WebSocket connection closed by server. Reconnecting in 2s...")

    if state.ping_timer, do: Process.cancel_timer(state.ping_timer)
    Process.send_after(self(), :register_and_connect, 2000)
    {:noreply, %{state | socket: nil, ping_timer: nil, handshake_done: false}}
  end

  defp heartbeat(%{socket: nil} = state), do: {:noreply, state}

  defp heartbeat(%{handshake_done: false} = state), do: {:noreply, state}

  defp heartbeat(state) do
    send_ping(state.socket, state)
    ping_timer = schedule_ping(state.ping_interval)
    {:noreply, %{state | ping_timer: ping_timer}}
  end

  defp run_simulated_build(build_id, console_url, state) do
    Logger.info("[HTTPTestAgent] Running simulated build tasks for: #{build_id}")

    report_progress(state, build_id, console_url, "Preparing", "Preparing build workspace...\n")
    Process.sleep(500)
    report_progress(state, build_id, console_url, "Building", "Executing build task: mix test\n")
    Process.sleep(500)
    post_log(console_url, "Build completed successfully.\n")
    send_report(state.socket, state.uuid, build_id, "Completed", "Idle", "Passed")

    Logger.info("[HTTPTestAgent] Finished simulated build: #{build_id}")
    {:noreply, %{state | runtime_status: "Idle", current_build: nil}}
  end

  defp report_progress(state, build_id, console_url, stage, log_line) do
    send_report(state.socket, state.uuid, build_id, stage, "Building", nil)
    post_log(console_url, log_line)
  end

  # Helper Functions

  defp host_to_string({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp host_to_string(host) when is_list(host), do: to_string(host)
  defp host_to_string(host) when is_binary(host), do: host

  defp register_agent(state) do
    host_str = host_to_string(state.host)

    with {:ok, token} <- fetch_token(state, host_str) do
      post_registration(state, host_str, token)
    end
  end

  defp fetch_token(state, host_str) do
    case Req.get("http://#{host_str}:#{state.port}/admin/agent/token?uuid=#{state.uuid}") do
      {:ok, %{status: 200, body: token}} -> {:ok, token}
      other -> {:error, {:token_request_failed, other}}
    end
  end

  defp post_registration(state, host_str, token) do
    case Req.post("http://#{host_str}:#{state.port}/admin/agent",
           form: registration_form(state, host_str, token)
         ) do
      {:ok, %{status: 200}} -> {:ok, token}
      other -> {:error, {:registration_post_failed, other}}
    end
  end

  defp registration_form(state, host_str, token) do
    [
      uuid: state.uuid,
      hostname: state.hostname,
      ipAddress: advertised_address(host_str),
      location: "./work-http",
      operatingSystem: "Simulated HTTP",
      usablespace: to_string(10 * 1024 * 1024 * 1024),
      token: token,
      supportsBuildCommandProtocol: "true",
      agentAutoRegisterResources: Enum.join(state.resources || [], ","),
      agentAutoRegisterEnvironments: Enum.join(state.environments || [], ",")
    ]
  end

  # The server cannot reach an agent back at "localhost", but it can at the loopback address.
  defp advertised_address("localhost"), do: "127.0.0.1"
  defp advertised_address(host_str), do: host_str

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
      {:ok, message} -> handle_message(message, state)
      {:error, _reason} -> state
    end
  end

  defp handle_websocket_frame(_frame, state), do: state

  defp handle_message(%{"action" => "build", "data" => data}, state) do
    build_id = data["buildId"]
    Logger.info("[HTTPTestAgent] Received build assignment for: #{build_id}")

    # The build runs in its own message, so the socket keeps reading.
    send(self(), {:run_simulated_build, build_id, data["consoleURI"]})

    %{state | runtime_status: "Building", current_build: build_id}
  end

  defp handle_message(%{"action" => "cancelBuild", "data" => %{"buildId" => build_id}}, state) do
    Logger.warning("[HTTPTestAgent] Received cancelBuild request for: #{build_id}")
    %{state | runtime_status: "Idle", current_build: nil}
  end

  defp handle_message(message, state) do
    # Other actions (e.g. setCookie, phx_reply) are not for this agent.
    Logger.debug("[HTTPTestAgent] Unhandled action: #{inspect(message)}")
    state
  end

  # WebSocket Framing implementation

  defp parse_frames(<<>>, acc), do: {Enum.reverse(acc), <<>>}

  defp parse_frames(buffer, acc) do
    case parse_frame(buffer) do
      {:ok, frame, rest} -> parse_frames(rest, [frame | acc])
      :incomplete -> {Enum.reverse(acc), buffer}
    end
  end

  # The three frame kinds this agent cares about, by opcode.
  @frame_kinds %{129 => :text, 137 => :ping, 136 => :close}
  @known_opcodes Map.keys(@frame_kinds)

  # A short payload is written into the length byte itself; 126 and 127 mean the
  # length follows in two or eight bytes.
  defp parse_frame(<<opcode, 126, len::16, payload::binary-size(len), rest::binary>>)
       when opcode in @known_opcodes do
    {:ok, {Map.fetch!(@frame_kinds, opcode), payload}, rest}
  end

  defp parse_frame(<<opcode, 127, len::64, payload::binary-size(len), rest::binary>>)
       when opcode in @known_opcodes do
    {:ok, {Map.fetch!(@frame_kinds, opcode), payload}, rest}
  end

  defp parse_frame(<<opcode, len, payload::binary-size(len), rest::binary>>)
       when opcode in @known_opcodes do
    {:ok, {Map.fetch!(@frame_kinds, opcode), payload}, rest}
  end

  defp parse_frame(buffer) when byte_size(buffer) < 2, do: :incomplete
  defp parse_frame(buffer), do: parse_long_frame(buffer)

  # A payload longer than one byte states its length in the bytes after the opcode.
  defp parse_long_frame(buffer) do
    <<_opcode, len_byte, _::binary>> = buffer
    len_field = len_byte &&& 0x7F
    needed = frame_needed_bytes(len_field)

    if byte_size(buffer) < needed do
      :incomplete
    else
      cut_frame(buffer, needed, frame_actual_len(buffer, len_field))
    end
  end

  defp cut_frame(buffer, needed, actual_len) do
    if byte_size(buffer) < needed + actual_len do
      :incomplete
    else
      {:ok, {opcode_of(buffer), binary_part(buffer, needed, actual_len)},
       binary_part(buffer, needed + actual_len, byte_size(buffer) - needed - actual_len)}
    end
  end

  defp opcode_of(<<opcode, _rest::binary>>), do: opcode

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
