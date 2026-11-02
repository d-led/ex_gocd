defmodule ExGoCD.Mcp.Render do
  @moduledoc """
  Turns a tool's answer into the lines a model reads.

  Every tool answers with two things: `text`, which is this module's work, and a
  `structured` map with the same facts for a program that would rather not parse
  prose. The text is deliberately plain — aligned columns rather than JSON — so a
  model can read a table of forty pipelines without spending its context on
  punctuation.

  Nothing here decides *what* is true; it only lays out what a context returned.
  A missing value is an em dash, not a zero: a stage that never ran and a stage
  that ran for no seconds are different answers.
  """

  @doc "A table cell: nil is unknown, a timestamp is formatted, a list is joined."
  @spec cell(term()) :: String.t()
  def cell(nil), do: "—"
  def cell(%DateTime{} = value), do: timestamp(value)
  def cell(%NaiveDateTime{} = value), do: timestamp(value)
  def cell(true), do: "yes"
  def cell(false), do: "no"
  def cell(value) when is_list(value), do: Enum.join(value, ", ")
  def cell(value) when is_binary(value), do: value
  def cell(value), do: to_string(value)

  @doc "An instant, for a person: `2026-11-02 09:41:00Z`."
  @spec timestamp(term()) :: String.t()
  def timestamp(nil), do: "—"

  def timestamp(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%SZ")

  def timestamp(%NaiveDateTime{} = value) do
    value |> DateTime.from_naive!("Etc/UTC") |> timestamp()
  end

  def timestamp(value), do: to_string(value)

  @doc """
  A column-aligned table with a header row.

  Columns are padded to the widest cell in them, and trailing whitespace is
  stripped, so the text is the same width a reader would draw by hand.
  """
  @spec table([String.t()], [[term()]]) :: String.t()
  def table(headers, rows) do
    cells = [Enum.map(headers, &cell/1) | Enum.map(rows, fn row -> Enum.map(row, &cell/1) end)]
    widths = column_widths(cells)

    cells
    |> Enum.map(fn row ->
      row
      |> Enum.with_index()
      |> Enum.map_join("  ", fn {value, index} -> pad(value, index, widths) end)
      |> trim()
    end)
    |> Enum.join("\n")
  end

  defp column_widths([header | _rest] = rows) do
    for index <- 0..(length(header) - 1), do: rows |> Enum.map(&width_at(&1, index)) |> Enum.max()
  end

  defp width_at(row, index), do: row |> Enum.at(index) |> to_string() |> String.length()

  # Every column is padded, and the joined row has its trailing spaces stripped:
  # the last column needs no padding, and a cell that is empty leaves one.
  defp pad(value, index, widths) do
    width = Enum.at(widths, index, 0) - String.length(value)
    if width > 0, do: value <> String.duplicate(" ", width), else: value
  end

  defp trim(line), do: String.trim_trailing(line)

  @doc "A `key: value` line per pair, in the order given."
  @spec kv([{String.t(), term()}]) :: String.t()
  def kv(pairs) do
    pairs
    |> Enum.map(fn {key, value} -> "#{key}: #{cell(value)}" end)
    |> Enum.join("\n")
  end

  @doc "A bulleted list."
  @spec bullets([String.t()]) :: String.t()
  def bullets(items) when is_list(items) do
    items |> Enum.map_join("\n", &("- " <> &1))
  end

  @doc """
  A duration a reader can compare with another one: `3.4s`, `2m 10s`, `1h 04m`.
  """
  @spec duration(term()) :: String.t()
  def duration(nil), do: "—"
  def duration(seconds) when is_float(seconds), do: duration(round(seconds))

  def duration(seconds) when is_integer(seconds) and seconds < 0, do: "—"

  def duration(seconds) when is_integer(seconds) and seconds < 60 do
    "#{Float.round(seconds / 1, 1)}s"
  end

  def duration(seconds) when is_integer(seconds) and seconds < 3600 do
    "#{div(seconds, 60)}m #{String.pad_leading(to_string(rem(seconds, 60)), 2, "0")}s"
  end

  def duration(seconds) when is_integer(seconds) do
    "#{div(seconds, 3600)}h #{String.pad_leading(to_string(div(rem(seconds, 3600), 60)), 2, "0")}m"
  end

  def duration(other), do: cell(other)

  @doc "The first `max` characters of a text, with a note when it was cut."
  @spec truncate(String.t(), pos_integer()) :: String.t()
  def truncate(text, max) when is_binary(text) do
    if String.length(text) <= max do
      text
    else
      String.slice(text, 0, max) <> "… (truncated)"
    end
  end

  @doc """
  The last `count` lines of a text.

  A build log's useful end is its last lines; an assistant that reads the first
  hundred of ten thousand learns that the build started, and nothing else.
  """
  @spec tail(String.t() | nil, pos_integer()) :: String.t()
  def tail(nil, _count), do: ""

  def tail(text, count) when is_binary(text) do
    lines = String.split(text, "\n", trim: true)

    if length(lines) <= count do
      Enum.join(lines, "\n")
    else
      "#{length(lines) - count} earlier line(s) not shown\n" <>
        (lines |> Enum.take(-count) |> Enum.join("\n"))
    end
  end
end
