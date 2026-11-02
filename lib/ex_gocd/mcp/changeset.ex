defmodule ExGoCD.Mcp.Changeset do
  @moduledoc """
  A refused changeset as one sentence a caller can act on.

  Ecto's error map is the right shape for a form and the wrong shape for a model
  reading a tool's refusal: `%{name: ["has already been taken"]}` becomes
  `name: has already been taken`, and several fields become one sentence rather
  than a nested structure the caller has to walk.
  """

  @spec message(Ecto.Changeset.t()) :: String.t()
  def message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)
  end
end
