# Copyright 2026 ex_gocd
# DynamicSupervisor for managing simulated OTP agents at scale.

defmodule ExGoCD.TestAgentSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Spawns a new simulated test agent under this supervisor.
  """
  def start_agent(opts \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {ExGoCD.TestAgent, opts})
  end

  @doc """
  Stops and terminates all currently running simulated agents.
  """
  def stop_all_agents do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.each(fn {_, pid, _, _} ->
      if is_pid(pid) and Process.alive?(pid) do
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      end
    end)
  end
end
