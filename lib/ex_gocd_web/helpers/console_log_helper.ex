defmodule ExGoCDWeb.ConsoleLogHelper do
  @moduledoc """
  Helper for parsing and formatting console logs with ANSI colors and clickable links,
  matching GoCD feature parity and user experience.
  """

  @doc """
  Formats console log text: parses ANSI escape sequences into styled HTML spans
  and converts URLs into clickable anchor links.
  """
  def format_log(nil), do: ""

  def format_log(log) when is_binary(log) do
    log
    |> ansi_to_html()
    |> replace_urls_with_links()
    |> Phoenix.HTML.raw()
  end

  # Tokenizes the log string by ANSI escape codes and wraps styled segments in HTML spans.
  defp ansi_to_html(text) do
    parse_ansi(text, 0, [])
  end

  defp parse_ansi("", open_spans, acc) do
    closes = String.duplicate("</span>", open_spans)
    IO.iodata_to_binary([acc, closes])
  end

  defp parse_ansi(text, open_spans, acc) do
    case :binary.split(text, ["\e[", "\u001b["]) do
      [plain] ->
        parse_ansi("", open_spans, [acc, Plug.HTML.html_escape(plain)])

      [plain, rest] ->
        case :binary.split(rest, "m") do
          [codes_str, rest_text] ->
            {span_html, new_open_spans} = process_ansi_codes(codes_str, open_spans)
            parse_ansi(rest_text, new_open_spans, [acc, Plug.HTML.html_escape(plain), span_html])

          [_no_m] ->
            parse_ansi("", open_spans, [acc, Plug.HTML.html_escape(text)])
        end
    end
  end

  defp process_ansi_codes(codes_str, open_spans) do
    codes =
      codes_str
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if Enum.empty?(codes) or "0" in codes do
      closes = String.duplicate("</span>", open_spans)
      {closes, 0}
    else
      classes = Enum.map(codes, &ansi_code_to_class/1) |> Enum.reject(&is_nil/1)

      if Enum.empty?(classes) do
        {"", open_spans}
      else
        {closes, new_open} = if open_spans > 0, do: {"</span>", 0}, else: {"", 0}
        class_str = Enum.join(classes, " ")
        {closes <> "<span class=\"#{class_str}\">", new_open + 1}
      end
    end
  end

  defp ansi_code_to_class("1"), do: "ansi-bold"
  defp ansi_code_to_class("3"), do: "ansi-italic"
  defp ansi_code_to_class("4"), do: "ansi-underline"
  # Foreground colors
  defp ansi_code_to_class("30"), do: "ansi-black"
  defp ansi_code_to_class("31"), do: "ansi-red"
  defp ansi_code_to_class("32"), do: "ansi-green"
  defp ansi_code_to_class("33"), do: "ansi-yellow"
  defp ansi_code_to_class("34"), do: "ansi-blue"
  defp ansi_code_to_class("35"), do: "ansi-magenta"
  defp ansi_code_to_class("36"), do: "ansi-cyan"
  defp ansi_code_to_class("37"), do: "ansi-white"
  # Bright foreground colors
  defp ansi_code_to_class("90"), do: "ansi-bright-black"
  defp ansi_code_to_class("91"), do: "ansi-bright-red"
  defp ansi_code_to_class("92"), do: "ansi-bright-green"
  defp ansi_code_to_class("93"), do: "ansi-bright-yellow"
  defp ansi_code_to_class("94"), do: "ansi-bright-blue"
  defp ansi_code_to_class("95"), do: "ansi-bright-magenta"
  defp ansi_code_to_class("96"), do: "ansi-bright-cyan"
  defp ansi_code_to_class("97"), do: "ansi-bright-white"
  # Background colors
  defp ansi_code_to_class("40"), do: "ansi-bg-black"
  defp ansi_code_to_class("41"), do: "ansi-bg-red"
  defp ansi_code_to_class("42"), do: "ansi-bg-green"
  defp ansi_code_to_class("43"), do: "ansi-bg-yellow"
  defp ansi_code_to_class("44"), do: "ansi-bg-blue"
  defp ansi_code_to_class("45"), do: "ansi-bg-magenta"
  defp ansi_code_to_class("46"), do: "ansi-bg-cyan"
  defp ansi_code_to_class("47"), do: "ansi-bg-white"
  # Default
  defp ansi_code_to_class(_), do: nil

  defp replace_urls_with_links(html) do
    ~r{(https?://[^\s<]+)}
    |> Regex.replace(html, fn url ->
      clean_url = url |> String.split("\"") |> hd() |> String.split("<") |> hd()

      ~s|<a href="#{clean_url}" target="_blank" rel="noopener" class="text-cyan-400 underline hover:text-cyan-300">#{clean_url}</a>|
    end)
  end
end
