defmodule ExGoCDWeb.GanttWindow do
  @moduledoc """
  The time span a Gantt chart covers.

  From the earliest thing that started to the latest thing that ended — or to now,
  for anything still running — padded so bars do not touch the edges. Both Gantt
  views on the site (pipeline activity by stage, stage details by job) asked the
  same question of their own rows.
  """

  @minimum_span_seconds 60
  # Five percent on each side.
  @padding_fraction 0.05

  @doc """
  `{from, to, span_seconds}` for items that carry `:scheduled_at`, `:completed_at`
  and something `running?` can recognise as still going.
  """
  def span(items, running?, now \\ DateTime.utc_now()) do
    starts = items |> Enum.map(& &1[:scheduled_at]) |> Enum.reject(&is_nil/1)
    ends = items |> Enum.map(&ended_at(&1, running?, now)) |> Enum.reject(&is_nil/1)

    padded(earliest(starts, now), latest(ends, now))
  end

  defp ended_at(item, running?, now) do
    case item[:completed_at] do
      nil -> if running?.(item), do: now
      completed -> completed
    end
  end

  defp earliest([], now), do: DateTime.add(now, -@minimum_span_seconds, :second)
  defp earliest(starts, now), do: Enum.min(starts, DateTime, fn -> now end)

  defp latest([], now), do: now
  defp latest(ends, now), do: Enum.max(ends, DateTime, fn -> now end)

  defp padded(from, to) do
    span = max(DateTime.diff(to, from, :second), @minimum_span_seconds)
    padding = round(span * @padding_fraction)

    {DateTime.add(from, -padding, :second), DateTime.add(to, padding, :second),
     span + 2 * padding}
  end
end
