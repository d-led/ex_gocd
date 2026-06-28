defmodule ExGoCD.HordeRegistry do
  @moduledoc """
  Distributed process registry via Horde.

  Singleton GenServers register their names here. Only one node
  in the cluster can hold a given key (keys: :unique).
  """
end
