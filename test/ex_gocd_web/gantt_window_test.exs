defmodule ExGoCDWeb.GanttWindowTest do
  @moduledoc """
  Both Gantt views on the site ask the same question of their own rows: from
  when to when does the chart go, and how much room does it leave at the ends.
  """
  use ExUnit.Case, async: true

  alias ExGoCDWeb.GanttWindow

  @now ~U[2026-11-02 12:00:00Z]

  test "spans from the earliest start to the latest finish, with room at both ends" do
    rows = [
      %{scheduled_at: ~U[2026-11-02 10:00:00Z], completed_at: ~U[2026-11-02 10:20:00Z]},
      %{scheduled_at: ~U[2026-11-02 10:10:00Z], completed_at: ~U[2026-11-02 11:00:00Z]}
    ]

    assert GanttWindow.span(rows, &running?/1, @now) ==
             {~U[2026-11-02 09:57:00Z], ~U[2026-11-02 11:03:00Z], 3960}
  end

  test "a row that is still running ends at now" do
    rows = [%{scheduled_at: ~U[2026-11-02 11:00:00Z], completed_at: nil, state: "Building"}]

    assert GanttWindow.span(rows, &running?/1, @now) ==
             {~U[2026-11-02 10:57:00Z], ~U[2026-11-02 12:03:00Z], 3960}
  end

  test "a span too short to see is stretched to a minute" do
    rows = [%{scheduled_at: @now, completed_at: @now}]

    assert GanttWindow.span(rows, &running?/1, @now) ==
             {~U[2026-11-02 11:59:57Z], ~U[2026-11-02 12:00:03Z], 66}
  end

  test "nothing to show is the minute up to now" do
    assert GanttWindow.span([], &running?/1, @now) ==
             {~U[2026-11-02 11:58:57Z], ~U[2026-11-02 12:00:03Z], 66}
  end

  test "a row that has not started yet does not open the window" do
    queued = [%{scheduled_at: nil, completed_at: nil, state: "Scheduled"}]

    assert GanttWindow.span(queued, &running?/1, @now) ==
             GanttWindow.span([], &running?/1, @now)
  end

  defp running?(row), do: row[:state] == "Building"
end
