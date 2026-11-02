defmodule ExGoCD.PluginNode.ObserverTest do
  @moduledoc """
  The observer prints what changed since its last look. A test machine has no
  other nodes, so the previous look is set directly — that is the state the
  callback is given, and the callback is what has behaviour.

  The observer registers under its own name, so this file runs alone.
  """
  use ExUnit.Case, async: false

  alias ExGoCD.PluginNode.Observer

  setup do
    start_supervised!(Observer)
    %{observer: Process.whereis(Observer)}
  end

  test "a node that is no longer there is reported", %{observer: pid} do
    :sys.replace_state(pid, fn state -> %{state | last_nodes: [:gone@nowhere]} end)

    assert output_of(pid, :tick) =~ "Node left: :gone@nowhere"
    assert :sys.get_state(pid).last_nodes == []
  end

  test "a look that finds the same nodes prints nothing", %{observer: pid} do
    assert output_of(pid, :tick) == ""
  end

  # The observer prints from its own process, so the buffer has to be that
  # process's group leader — capturing in the test process would catch nothing.
  defp output_of(pid, message) do
    {:ok, buffer} = StringIO.open("")
    # `group_leader/2` answers `true` rather than the leader it replaced, so the
    # old one is read first.
    {:group_leader, previous} = Process.info(pid, :group_leader)
    :erlang.group_leader(buffer, pid)

    send(pid, message)
    # The tick is in the mailbox before this call, so its output is written.
    :sys.get_state(pid)

    {_input, output} = StringIO.contents(buffer)
    :erlang.group_leader(previous, pid)
    StringIO.close(buffer)
    output
  end
end
