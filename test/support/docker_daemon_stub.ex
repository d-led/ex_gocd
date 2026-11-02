defmodule ExGoCD.DockerDaemonStub do
  @moduledoc """
  A stand-in for the Docker daemon, listening on a Unix socket.

  `ExGoCD.Docker` speaks HTTP over a socket path and nothing else, so the way to
  test it without a daemon is to be the daemon: accept the next request, hand it
  to the test, and answer with the status and body the test asked for.
  """

  import ExUnit.Assertions, only: [flunk: 1]
  import ExUnit.Callbacks, only: [on_exit: 1]

  @timeout 5_000

  @doc """
  Starts a daemon that answers one request with `status` and `body`.

  The returned map carries the `socket` to hand to the client; `request/1` gives
  back what the client sent.
  """
  def serving(reply) do
    socket = Path.join(System.tmp_dir!(), "dg#{token()}.sock")
    on_exit(fn -> File.rm(socket) end)

    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        ifaddr: {:local, socket},
        active: false,
        packet: :raw,
        reuseaddr: true
      ])

    caller = self()
    spawn_link(fn -> answer_one(listen, socket, Map.new(reply), caller) end)

    %{socket: socket}
  end

  @doc "The request the client sent to this daemon, as `%{method:, path:, body:}`."
  def request(%{socket: socket}) do
    receive do
      {:request, ^socket, request} -> request
    after
      @timeout -> flunk("the stub daemon on #{socket} never saw a request")
    end
  end

  # A random name, not a counter: counters restart with the VM and a socket file
  # from an earlier run is enough to make the next bind fail.
  defp token, do: 6 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  defp answer_one(listen, socket, reply, caller) do
    {:ok, conn} = :gen_tcp.accept(listen)
    send(caller, {:request, socket, read_request(conn)})
    :gen_tcp.send(conn, response(reply))
    :gen_tcp.close(conn)
    :gen_tcp.close(listen)
    File.rm(socket)
  end

  defp read_request(conn, buffer \\ "") do
    if String.contains?(buffer, "\r\n\r\n") do
      [head, body] = String.split(buffer, "\r\n\r\n", parts: 2)

      parse(head, read_body(conn, body, content_length(head)))
    else
      {:ok, chunk} = :gen_tcp.recv(conn, 0, @timeout)
      read_request(conn, buffer <> chunk)
    end
  end

  defp read_body(_conn, body, wanted) when byte_size(body) >= wanted, do: body

  defp read_body(conn, body, wanted) do
    {:ok, chunk} = :gen_tcp.recv(conn, 0, @timeout)
    read_body(conn, body <> chunk, wanted)
  end

  defp content_length(head) do
    case Regex.run(~r/^content-length: *(\d+)/im, head) do
      [_, length] -> String.to_integer(length)
      nil -> 0
    end
  end

  defp parse(head, body) do
    [request_line | _headers] = String.split(head, "\r\n")
    [method, path | _version] = String.split(request_line, " ")

    %{method: method, path: path, body: body}
  end

  defp response(%{status: status} = reply) do
    body = reply |> Map.get(:body, "") |> encode()

    "HTTP/1.1 #{status} #{reason(status)}\r\n" <>
      "Content-Type: #{content_type(Map.get(reply, :body, ""))}\r\n" <>
      "Content-Length: #{byte_size(body)}\r\n" <>
      "Connection: close\r\n\r\n" <> body
  end

  # The daemon answers /_ping with text and everything else with JSON, and the
  # client reads a body as JSON when the type says so.
  defp content_type(body) when is_map(body) or is_list(body), do: "application/json"
  defp content_type(_body), do: "text/plain"

  defp encode(body) when is_binary(body), do: body
  defp encode(body), do: Jason.encode!(body)

  defp reason(200), do: "OK"
  defp reason(201), do: "Created"
  defp reason(204), do: "No Content"
  defp reason(304), do: "Not Modified"
  defp reason(404), do: "Not Found"
  defp reason(500), do: "Internal Server Error"
  defp reason(_status), do: "Status"
end
