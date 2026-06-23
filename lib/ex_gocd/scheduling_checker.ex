defmodule ExGoCD.SchedulingChecker do
  @moduledoc """
  Behaviour for pre-trigger scheduling checks.

  Mirrors GoCD's `SchedulingChecker` interface. Each checker returns
  `:ok` or `{:error, reason}` where reason is an atom like
  `:pipeline_locked`, `:pipeline_paused`, `:already_triggered`, etc.

  Use `ExGoCD.SchedulingChecker.Composite` to run multiple checkers
  in sequence, stopping at the first failure.
  """

  @callback check(pipeline_name :: String.t()) :: :ok | {:error, atom()}

  defmacro __using__(_opts) do
    quote do
      @behaviour ExGoCD.SchedulingChecker
    end
  end

  defmodule Composite do
    @moduledoc """
    Runs a list of `SchedulingChecker` implementations in order.
    Stops at the first `{:error, reason}`. Returns `:ok` if all pass.
    """

    @spec check([module()], String.t()) :: :ok | {:error, atom()}
    def check(checkers, pipeline_name) when is_list(checkers) do
      Enum.reduce_while(checkers, :ok, fn checker, :ok ->
        case checker.check(pipeline_name) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end
end
