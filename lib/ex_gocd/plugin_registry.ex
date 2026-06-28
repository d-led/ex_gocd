defmodule ExGoCD.Plugin.Registry do
  @moduledoc """
  Reads plugin modules from `config :ex_gocd, :plugins` and validates their
  behaviour implementations. Answers `get(:agent_selector)` → module | nil.

  Configured in config.exs:

      config :ex_gocd, :plugins, [
        agent_selector: MyApp.CorpPolicy,
        pipeline_grouper: MyApp.TeamGrouper
      ]

  Plugins are loaded lazily on first `get/1` call. Validation failures
  are logged as warnings — the slot returns `nil` (fall back to default).
  """

  use GenServer

  @slots [:agent_selector, :auth_provider, :pipeline_grouper, :org_hierarchy, :notification_sink]

  # -- Client API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the module registered for the given slot, or nil.
  """
  @spec get(atom()) :: module() | nil
  def get(slot) when slot in @slots do
    GenServer.call(__MODULE__, {:get, slot})
  end

  @doc """
  Lists all registered slots with their module or nil.
  """
  @spec list() :: keyword()
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # -- Callbacks --

  @impl true
  def init(_opts) do
    plugins = Application.get_env(:ex_gocd, :plugins, [])
    state = validate_and_load(plugins)
    {:ok, state}
  end

  @impl true
  def handle_call({:get, slot}, _from, state) do
    {:reply, Map.get(state, slot), state}
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.to_list(state), state}
  end

  # -- Private --

  defp validate_and_load(plugins) do
    Enum.reduce(@slots, %{}, fn slot, acc ->
      case Keyword.get(plugins, slot) do
        nil ->
          Map.put(acc, slot, nil)

        mod when is_atom(mod) ->
          if Code.ensure_loaded?(mod) do
            if valid_behaviour?(slot, mod) do
              Map.put(acc, slot, mod)
            else
              IO.warn(
                "[PluginRegistry] #{inspect(mod)} for slot #{slot} does not implement required behaviour",
                []
              )

              Map.put(acc, slot, nil)
            end
          else
            IO.warn("[PluginRegistry] module #{inspect(mod)} for slot #{slot} could not be loaded", [])
            Map.put(acc, slot, nil)
          end
      end
    end)
  end

  defp valid_behaviour?(:agent_selector, mod), do: behaviour_loaded?(mod, ExGoCD.Plugin.AgentSelector)
  defp valid_behaviour?(:auth_provider, mod), do: behaviour_loaded?(mod, ExGoCD.Plugin.AuthProvider)
  defp valid_behaviour?(:pipeline_grouper, mod), do: behaviour_loaded?(mod, ExGoCD.Plugin.PipelineGrouper)
  defp valid_behaviour?(:org_hierarchy, mod), do: behaviour_loaded?(mod, ExGoCD.Plugin.OrgHierarchy)
  defp valid_behaviour?(:notification_sink, mod), do: behaviour_loaded?(mod, ExGoCD.Plugin.NotificationSink)

  defp behaviour_loaded?(mod, behaviour) do
    case Code.ensure_loaded(behaviour) do
      {:module, ^behaviour} ->
        behaviour.behaviour_info(:callbacks)
        |> Enum.all?(fn {name, arity} -> function_exported?(mod, name, arity) end)

      _ ->
        false
    end
  end
end
