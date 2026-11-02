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
    content =
      log
      |> ansi_to_html()
      |> replace_urls_with_links()

    {:safe, content}
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

  # The escape code names the style; there is nothing to decide, so the codes are
  # a table rather than thirty clauses.
  @ansi_classes %{
    "1" => "ansi-bold",
    "3" => "ansi-italic",
    "4" => "ansi-underline",
    # Foreground colors
    "30" => "ansi-black",
    "31" => "ansi-red",
    "32" => "ansi-green",
    "33" => "ansi-yellow",
    "34" => "ansi-blue",
    "35" => "ansi-magenta",
    "36" => "ansi-cyan",
    "37" => "ansi-white",
    # Bright foreground colors
    "90" => "ansi-bright-black",
    "91" => "ansi-bright-red",
    "92" => "ansi-bright-green",
    "93" => "ansi-bright-yellow",
    "94" => "ansi-bright-blue",
    "95" => "ansi-bright-magenta",
    "96" => "ansi-bright-cyan",
    "97" => "ansi-bright-white",
    # Background colors
    "40" => "ansi-bg-black",
    "41" => "ansi-bg-red",
    "42" => "ansi-bg-green",
    "43" => "ansi-bg-yellow",
    "44" => "ansi-bg-blue",
    "45" => "ansi-bg-magenta",
    "46" => "ansi-bg-cyan",
    "47" => "ansi-bg-white"
  }

  defp ansi_code_to_class(code), do: Map.get(@ansi_classes, code)

  defp replace_urls_with_links(html) do
    ~r{(https?://[^\s<]+)}
    |> Regex.replace(html, fn url ->
      clean_url = url |> String.split("\"") |> hd() |> String.split("<") |> hd()

      ~s|<a href="#{clean_url}" target="_blank" rel="noopener" class="text-cyan-400 underline hover:text-cyan-300">#{clean_url}</a>|
    end)
  end
end
