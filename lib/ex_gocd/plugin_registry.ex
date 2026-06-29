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

  @doc """
  Aggregates UI links from all registered plugins. Each plugin may export
  an optional `ui_links/0` returning `[{name, url}]`.
  """
  @spec ui_links() :: [{String.t(), String.t()}]
  def ui_links do
    GenServer.call(__MODULE__, :ui_links)
  end

  @doc """
  Self-registration endpoint for external plugin nodes. Plugins authenticate
  with a shared secret (set via PLUGIN_SECRET env or config) and register
  for a slot. This is how standalone plugin OTP apps join the cluster.

  Returns `:ok` on success, `{:error, :invalid_secret}` or `{:error, :invalid_slot}`.
  """
  @spec register(atom(), module(), String.t()) :: :ok | {:error, atom()}
  def register(slot, module, secret) when slot in @slots do
    GenServer.call(__MODULE__, {:register, slot, module, secret})
  end

  # -- Callbacks --

  @impl true
  def init(_opts) do
    plugins = Application.get_env(:ex_gocd, :plugins, [])

    secret =
      Application.get_env(:ex_gocd, :plugin_secret) || System.get_env("PLUGIN_SECRET") || ""

    # Subscribe to plugin self-registration broadcasts
    Phoenix.PubSub.subscribe(ExGoCD.PubSub, "plugin:register")

    state = %{slots: validate_and_load(plugins), secret: secret, ui_links: %{}}
    {:ok, state}
  end

  @impl true
  def handle_info({:plugin_register, slot, module, secret}, state) do
    configured_secret = Map.get(state, :secret, "")

    if slot in @slots and valid_secret?(configured_secret, secret) do
      IO.puts("[PluginRegistry] Registered #{inspect(module)} as #{slot}")
      ExGoCD.ClusterEventLog.record(:plugin_registered, %{slot: slot, module: module})
      {:noreply, put_in(state, [:slots, slot], module)}
    else
      IO.warn("[PluginRegistry] Rejected #{inspect(module)} for #{slot}: invalid secret")
      {:noreply, state}
    end
  end

  def handle_info({:plugin_ui_links, slot, secret, links}, state) do
    configured_secret = Map.get(state, :secret, "")

    if slot in @slots and valid_secret?(configured_secret, secret) do
      {:noreply, put_in(state, [:ui_links, slot], links)}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:get, slot}, _from, state) do
    slots = Map.get(state, :slots, state)
    {:reply, Map.get(slots, slot), state}
  end

  def handle_call(:list, _from, state) do
    slots = Map.get(state, :slots, state)
    {:reply, Map.to_list(slots), state}
  end

  def handle_call(:ui_links, _from, state) do
    links =
      Map.get(state, :ui_links, %{})
      |> Map.values()
      |> List.flatten()

    {:reply, links, state}
  end

  def handle_call({:register, slot, module, secret}, _from, state) do
    if valid_secret?(state.secret, secret) do
      {:reply, :ok, put_in(state.slots[slot], module)}
    else
      {:reply, {:error, :invalid_secret}, state}
    end
  end

  # -- Private --

  defp valid_secret?("", _), do: true
  defp valid_secret?(configured, supplied), do: Plug.Crypto.secure_compare(configured, supplied)

  defp validate_and_load(plugins) do
    Enum.reduce(@slots, %{}, fn slot, acc ->
      Map.put(acc, slot, load_slot(slot, Keyword.get(plugins, slot)))
    end)
  end

  defp load_slot(_slot, nil), do: nil

  defp load_slot(slot, mod) when is_atom(mod) do
    cond do
      not Code.ensure_loaded?(mod) ->
        IO.warn(
          "[PluginRegistry] module #{inspect(mod)} for slot #{slot} could not be loaded",
          []
        )

        nil

      not valid_behaviour?(slot, mod) ->
        IO.warn(
          "[PluginRegistry] #{inspect(mod)} for slot #{slot} does not implement required behaviour",
          []
        )

        nil

      true ->
        mod
    end
  end

  defp valid_behaviour?(:agent_selector, mod),
    do: behaviour_loaded?(mod, ExGoCD.Plugin.AgentSelector)

  defp valid_behaviour?(:auth_provider, mod),
    do: behaviour_loaded?(mod, ExGoCD.Plugin.AuthProvider)

  defp valid_behaviour?(:pipeline_grouper, mod),
    do: behaviour_loaded?(mod, ExGoCD.Plugin.PipelineGrouper)

  defp valid_behaviour?(:org_hierarchy, mod),
    do: behaviour_loaded?(mod, ExGoCD.Plugin.OrgHierarchy)

  defp valid_behaviour?(:notification_sink, mod),
    do: behaviour_loaded?(mod, ExGoCD.Plugin.NotificationSink)

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
