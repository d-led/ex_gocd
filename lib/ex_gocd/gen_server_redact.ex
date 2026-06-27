defmodule ExGoCD.GenServerRedact do
  @moduledoc """
  Safe crash logging for GenServers — prevents secrets from leaking into
  SASL crash reports and `sys:get_status/1` dumps.

  ## OTP guidance

  When a GenServer terminates abnormally, SASL's error logger calls
  `sys:get_status/1`, which calls `c:GenServer.format_status/2`.
  Without a custom implementation, the entire process state and the last
  message are dumped — including API keys, passwords, and tokens.

  Ericsson/OTP design rule: every GenServer that handles credentials or
  receives authenticated requests MUST implement `format_status/2`.

  ## Usage

      use ExGoCD.GenServerRedact

  This makes `format_status/2` overridable (if not already) and provides
  a default that redacts known-sensitive keys. Individual GenServers can
  override for custom redaction rules.

  ## Redacted patterns

  Keys matching any of these regex patterns are replaced with
  `"***REDACTED***"` (checked up to 3 levels deep):
  - `password`, `passwd`, `secret`, `token`
  - `_key` suffix (e.g. `api_key`, `access_key`, `secret_key`)
  - `cookie`, `credential`, `bearer`
  """

  @redacted_value "***REDACTED***"
  @max_depth 3

  @sensitive_patterns [
    ~r/password/i,
    ~r/passwd/i,
    ~r/secret/i,
    ~r/token/i,
    ~r/_key/i,
    ~r/cookie/i,
    ~r/credential/i,
    ~r/bearer/i
  ]

  defmacro __using__(_opts) do
    quote do
      @impl true
      def format_status(reason, [pdict, state]) do
        [
          ExGoCD.GenServerRedact.redact_pdict(pdict),
          ExGoCD.GenServerRedact.redact(state)
        ]
      end
    end
  end

  @doc """
  Recursively redacts sensitive values from any term.
  Safe for maps, lists, tuples, and atoms.
  """
  def redact(term), do: redact(term, 0)

  defp redact(%{__struct__: _} = struct, depth) when depth < @max_depth do
    struct
    |> Map.from_struct()
    |> redact_map(depth)
  end

  defp redact(map, depth) when is_map(map) and depth < @max_depth do
    redact_map(map, depth)
  end

  defp redact(list, depth) when is_list(list) and depth < @max_depth do
    Enum.map(list, &redact(&1, depth + 1))
  end

  defp redact(tuple, depth) when is_tuple(tuple) and depth < @max_depth do
    tuple |> Tuple.to_list() |> Enum.map(&redact(&1, depth + 1)) |> List.to_tuple()
  end

  defp redact(term, _depth), do: term

  defp redact_map(map, depth) do
    Map.new(map, fn {key, value} ->
      if sensitive_key?(key) do
        {key, @redacted_value}
      else
        {key, redact(value, depth + 1)}
      end
    end)
  end

  @doc """
  Redacts process dictionary entries whose key looks sensitive.
  """
  def redact_pdict(pdict) when is_list(pdict) do
    Enum.map(pdict, fn
      {key, value} when is_atom(key) ->
        if sensitive_key?(key), do: {key, @redacted_value}, else: {key, value}

      other ->
        other
    end)
  end

  def redact_pdict(pdict), do: pdict

  defp sensitive_key?(key) when is_atom(key), do: sensitive_key?(Atom.to_string(key))
  defp sensitive_key?(key) when is_binary(key), do: Enum.any?(@sensitive_patterns, &Regex.match?(&1, key))
  defp sensitive_key?(_), do: false
end
