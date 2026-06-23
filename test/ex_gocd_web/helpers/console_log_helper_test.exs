defmodule ExGoCDWeb.ConsoleLogHelperTest do
  use ExUnit.Case, async: true

  alias ExGoCDWeb.ConsoleLogHelper

  describe "format_log/1" do
    test "escapes raw HTML in plain text" do
      formatted = ConsoleLogHelper.format_log("hello <script>alert(1)</script> world")

      assert Phoenix.HTML.safe_to_string(formatted) ==
               "hello &lt;script&gt;alert(1)&lt;/script&gt; world"
    end

    test "parses single ANSI color code and wraps it in a styled span" do
      formatted = ConsoleLogHelper.format_log("\e[32mgreen text")

      assert Phoenix.HTML.safe_to_string(formatted) ==
               "<span class=\"ansi-green\">green text</span>"
    end

    test "parses semicolon-separated ANSI codes" do
      formatted = ConsoleLogHelper.format_log("\e[1;33myellow bold")

      assert Phoenix.HTML.safe_to_string(formatted) ==
               "<span class=\"ansi-bold ansi-yellow\">yellow bold</span>"
    end

    test "closes open spans on reset code (0)" do
      formatted = ConsoleLogHelper.format_log("\e[31mred\e[0m plain")
      assert Phoenix.HTML.safe_to_string(formatted) == "<span class=\"ansi-red\">red</span> plain"
    end

    test "closes open spans on empty reset code" do
      formatted = ConsoleLogHelper.format_log("\e[34mblue\e[m plain")

      assert Phoenix.HTML.safe_to_string(formatted) ==
               "<span class=\"ansi-blue\">blue</span> plain"
    end

    test "parses background color code" do
      formatted = ConsoleLogHelper.format_log("\e[44mblue bg")

      assert Phoenix.HTML.safe_to_string(formatted) ==
               "<span class=\"ansi-bg-blue\">blue bg</span>"
    end

    test "replaces URLs with clickable links" do
      formatted = ConsoleLogHelper.format_log("check https://github.com/d-led/ex_gocd out")
      html = Phoenix.HTML.safe_to_string(formatted)
      assert html =~ "<a href=\"https://github.com/d-led/ex_gocd\""
      assert html =~ "class=\"text-cyan-400 underline hover:text-cyan-300\""
    end

    test "combines ANSI styling and URL matching safely" do
      formatted = ConsoleLogHelper.format_log("\e[32mgreen link https://example.com/test\e[0m")
      html = Phoenix.HTML.safe_to_string(formatted)
      assert html =~ "<span class=\"ansi-green\">green link <a href=\"https://example.com/test\""
      assert html =~ "</a></span>"
    end
  end
end
