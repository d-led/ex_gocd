defmodule ExGoCD.LoggerJSON do
  @moduledoc """
  Custom Elixir logger backend that writes JSON lines to a file.
  Fluent Bit tails this file and forwards to Loki.

  Configure in dev.exs:
    config :logger, backends: [:console, ExGoCD.LoggerJSON]
    config :logger, ExGoCD.LoggerJSON, path: "/tmp/ex_gocd_server.log"

  Console logging continues as normal. JSON file is additive.
  """
  @behaviour :gen_event

  defstruct path: nil, io_device: nil, level: nil

  @doc "Adds this backend to the Elixir logger."
  def add_backend(opts \\ []) do
    LoggerBackends.add(__MODULE__, opts)
  end

  @impl true
  def init({__MODULE__, opts}) do
    do_init(opts)
  end

  # Handle :backends config format (module only, no opts)
  def init(__MODULE__) do
    do_init([])
  end

  defp do_init(opts) do
    path = Keyword.get(opts, :path, "/tmp/ex_gocd_server.log")
    level = Keyword.get(opts, :level, :debug)

    {:ok, io} = File.open(path, [:append, :utf8])
    state = %__MODULE__{path: path, io_device: io, level: level}
    {:ok, state}
  end

  @impl true
  def handle_call({:configure, opts}, state) do
    path = Keyword.get(opts, :path, state.path)
    level = Keyword.get(opts, :level, state.level)

    if path != state.path do
      File.close(state.io_device)
      {:ok, io} = File.open(path, [:append, :utf8])
      {:ok, :ok, %{state | path: path, io_device: io, level: level}}
    else
      {:ok, :ok, %{state | level: level}}
    end
  end

  @impl true
  def handle_event({level, _gl, {Logger, message, timestamp, metadata}}, state) do
    if Logger.compare_levels(level, state.level) != :lt do
      entry = %{
        "level" => Atom.to_string(level),
        "message" => IO.iodata_to_binary(message),
        "timestamp" => format_timestamp(timestamp),
        "module" => get_in(metadata, [:module]) || "unknown"
      }

      json_line = Jason.encode_to_iodata!(entry) |> IO.iodata_to_binary()
      IO.puts(state.io_device, json_line)
    end

    {:ok, state}
  end

  def handle_event(:flush, state), do: {:ok, state}
  def handle_event(_event, state), do: {:ok, state}

  @impl true
  def handle_info(_msg, state), do: {:ok, state}

  @impl true
  def code_change(_old, state, _extra), do: {:ok, state}

  defp format_timestamp({date, {h, m, s, us}}) do
    # us is microseconds in Erlang timestamp
    time = Time.new!(h, m, s, {us, 6})
    {:ok, ndt} = NaiveDateTime.new(date, time)
    NaiveDateTime.to_iso8601(ndt)
  end
end
