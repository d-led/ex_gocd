defmodule ExGoCD.GenServerRedact do
  @moduledoc """
  Safe crash logging for GenServers — prevents secrets from leaking into
  SASL crash reports and `sys:get_status/1` dumps.

  ## OTP guidance

  When a GenServer terminates abnormally, SASL's error logger calls
  `sys:get_status/1`, which calls `format_status(:terminate, [pdict, state])`.
  Without a custom implementation, the entire process state and the last
  message are dumped — including API keys, passwords, and tokens.

  Ericsson/OTP design rule: every GenServer that handles credentials or
  receives authenticated requests MUST implement `format_status/2`.

  ## Usage

      use ExGoCD.GenServerRedact

  This adds a safe `format_status/2` that redacts known-sensitive keys
  from maps in state and process dictionary.  Individual GenServers can
  override `c:GenServer.format_status/2` for custom redaction rules.

  ## Redacted keys

  The following keys are replaced with `"***REDACTED***"` in any map
  (nested up to 3 levels deep):
  - password, pass, pwd
  - token, api_key, apikey, secret, access_key, secret_key
  - cookie, auth, credential, bearer
  - private_key, ssh_key, tls_key
  """

  @redacted_value "***REDACTED***"
  @max_depth 3

  @sensitive_keys ~w(
    password pass pwd
    token api_key apikey secret access_key secret_key
    cookie auth credential bearer
    private_key ssh_key tls_key
  )
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
        [ExGoCD.GenServerRedact.redact_pdict(pdict), ExGoCD.GenServerRedact.redact(state)]
        |> ExGoCD.GenServerRedact.handle_format_status(reason)
      end

      @doc false
      def format_status(_reason, [_pdict, _state] = result), do: result
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

  @doc false
  def handle_format_status([pdict, state], :terminate) do
    [pdict, state]
  end

  def handle_format_status([pdict, state], _reason) do
    [pdict, state]
  end

  defp sensitive_key?(key) when is_atom(key), do: sensitive_key?(Atom.to_string(key))
  defp sensitive_key?(key) when is_binary(key), do: Enum.any?(@sensitive_patterns, &Regex.match?(&1, key))
  defp sensitive_key?(_), do: false
end
