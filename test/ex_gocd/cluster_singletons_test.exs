defmodule ExGoCD.ClusterSingletonsTest do
  @moduledoc """
  The cluster's singletons were started by a `Task` that ran once at boot, so when
  the Horde supervisor was replaced — a poller crashing past its restart budget was
  enough — every singleton was gone until the node restarted.

  The starter is held to two things here: it asks the supervisor for every child,
  and it asks again when the supervisor is replaced. A stand-in supervisor records
  the asks; Horde itself needs a cluster, and what is being tested is the starter's
  reaction, not Horde's bookkeeping.
  """
  use ExUnit.Case, async: true

  alias ExGoCD.ClusterSingletons

  defmodule Child do
    @moduledoc false
    use GenServer
    def start_link(_), do: GenServer.start_link(__MODULE__, nil)
    def init(state), do: {:ok, state}
  end

  defmodule OtherChild do
    @moduledoc false
    use GenServer
    def start_link(_), do: GenServer.start_link(__MODULE__, nil)
    def init(state), do: {:ok, state}
  end

  # Speaks the one message Horde's start_child sends, and reports it to the test.
  defmodule StandInSupervisor do
    @moduledoc false
    use GenServer

    @impl true
    def init(report_to), do: {:ok, report_to}

    @impl true
    def handle_call({:start_child, spec}, _from, report_to) do
      send(report_to, {:start_child, spec.id})
      {:reply, {:ok, self()}, report_to}
    end
  end

  setup do
    supervisor = :"stand_in_sup_#{System.unique_integer([:positive])}"
    starter = :"singletons_#{System.unique_integer([:positive])}"

    {:ok, supervisor: supervisor, starter: starter}
  end

  test "asks for every child", %{supervisor: supervisor, starter: starter} do
    start_supervisor(supervisor)
    start_starter(starter, supervisor)

    asked = asked_for()
    assert Child in asked
    assert OtherChild in asked
  end

  test "asks again when the supervisor is replaced", %{supervisor: supervisor, starter: starter} do
    pid = start_supervisor(supervisor)
    start_starter(starter, supervisor)
    _ = asked_for()

    stop_supervisor(pid)
    start_supervisor(supervisor)

    assert eventually(fn -> Child in asked_for() end)
  end

  test "waits for a supervisor that is not there yet", %{supervisor: supervisor, starter: starter} do
    start_starter(starter, supervisor)

    refute_received {:start_child, _}

    start_supervisor(supervisor)

    assert eventually(fn -> Child in asked_for() end)
  end

  defp asked_for(acc \\ []) do
    receive do
      {:start_child, id} -> asked_for([id | acc])
    after
      20 -> acc
    end
  end

  # Started directly and unlinked: a supervised child is restarted when killed,
  # and a linked one takes the test down with it.
  defp start_supervisor(name) do
    {:ok, pid} = GenServer.start(StandInSupervisor, self(), name: name)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    pid
  end

  defp stop_supervisor(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      2_000 -> flunk("supervisor did not stop")
    end
  end

  defp start_starter(name, supervisor) do
    start_supervised!(
      {ClusterSingletons,
       name: name, supervisor: supervisor, children: [Child, OtherChild], retry: 10},
      id: name
    )
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && eventually(fun, attempts - 1)
    end
  end
end
