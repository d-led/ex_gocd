defmodule ExGoCDWeb.FormsTest do
  @moduledoc """
  LiveView keeps a form's input across a crash or a reconnect only for forms it
  can name: one without an id loses whatever was typed. It warns, but only while
  tests run, so a warning nobody reads is the same as no warning.

  Two forms were in that state — the pipeline wizard and the admin pipeline
  search — and thirty-one warnings came from them.
  """
  use ExUnit.Case, async: true

  test "every LiveView form has an id" do
    assert forms_without_ids() == []
  end

  defp forms_without_ids do
    for path <- Path.wildcard("lib/ex_gocd_web/**/*.{ex,heex}"),
        not String.starts_with?(path, "lib/ex_gocd_web/components/"),
        tag <- form_tags(File.read!(path)),
        String.contains?(tag, "phx-change"),
        not String.contains?(tag, "id="),
        do: "#{path}: #{String.slice(tag, 0, 90)}"
  end

  defp form_tags(source) do
    ~r/<\s*\.?form\b[^>]*>/s
    |> Regex.scan(source)
    |> Enum.map(&hd/1)
  end
end
