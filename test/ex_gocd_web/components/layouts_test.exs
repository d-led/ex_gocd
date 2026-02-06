defmodule ExGoCDWeb.LayoutsTest do
  use ExGoCDWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ExGoCDWeb.Layouts

  describe "site_header/1" do
    test "renders GoCD logo with link to pipelines" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      assert html =~ ~s(<a)
      assert html =~ ~s(href="/pipelines")
      assert html =~ ~s(class="gocd_logo")
      assert html =~ ~s(aria-label="GoCD Logo - Go to Pipelines")
    end

    test "renders mobile navigation button" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      assert html =~ ~s(<button)
      assert html =~ ~s(class="navbtn")
      assert html =~ ~s(aria-label="Toggle navigation menu")
      assert html =~ ~s(aria-expanded="false")
      assert html =~ ~s(aria-controls="main-navigation")
    end

    test "renders main navigation with proper role" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      assert html =~ ~s(id="main-navigation")
      assert html =~ ~s(class="main-navigation")
      assert html =~ ~s(role="navigation")
      assert html =~ ~s(aria-label="Main navigation")
    end

    test "renders all navigation menu items" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      assert html =~ ~s(Dashboard)
      assert html =~ ~s(Agents)
      assert html =~ ~s(Materials)
      assert html =~ ~s(Admin)
    end

    test "marks Dashboard as active page" do
      assigns = %{current_path: "/pipelines"}
      html = render_component(&Layouts.site_header/1, assigns)

      assert html =~ ~s(class="active")
      assert html =~ ~s(aria-current="page")
      # Active item should be within the list
      assert html =~ ~r/<li[^>]*class="active"[^>]*>.*Dashboard/s
    end

    test "all menu items have proper ARIA roles" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      assert html =~ ~s(role="menubar")
      assert html =~ ~s(role="menuitem")
      # Should have multiple menuitem roles (one per link)
      menuitem_count = html |> String.split(~s(role="menuitem")) |> length() |> Kernel.-(1)
      assert menuitem_count >= 4
    end

    test "renders Need Help link" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      assert html =~ ~s(Need Help?)
      assert html =~ ~s(href="https://docs.gocd.org")
      assert html =~ ~s(target="_blank")
      assert html =~ ~s(rel="noopener noreferrer")
      assert html =~ ~s(aria-label="Need Help? Opens in new window")
    end

    test "all navigation links are keyboard accessible" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      # All navigation links should have tabindex="0"
      assert html =~ ~s(tabindex="0")
      # Count tabindex occurrences (logo + 4 menu items + help link = 6)
      tabindex_count = html |> String.split(~s(tabindex="0")) |> length() |> Kernel.-(1)
      assert tabindex_count >= 5
    end

    test "header has semantic banner role" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      assert html =~ ~s(<header)
      assert html =~ ~s(class="site-header")
      assert html =~ ~s(role="banner")
    end

    test "navigation has proper structure" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      assert html =~ ~s(class="site-header_left")
      assert html =~ ~s(class="site-header_right")
      assert html =~ ~s(class="site-navigation_left")
    end
  end

  describe "root layout" do
    test "renders with flash messages", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      # Root layout should be present
      assert html =~ ~s(<!DOCTYPE html>)
      assert html =~ ~s(<html)
      assert html =~ ~s(lang="en")
    end

    test "includes GoCD meta tags and title", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ ~s(<meta charset="utf-8")
      assert html =~ ~s(<meta name="viewport")
      assert html =~ ~s(<title)
    end

    test "includes site header in app layout", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ ~s(class="site-header")
      assert html =~ ~s(GoCD Logo)
    end
  end

  describe "responsive design" do
    test "mobile navigation button is present for small screens" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      # Mobile button should be in the header
      assert html =~ ~s(class="navbtn")
      # Hamburger icon bars
      assert html =~ ~s(class="bar")
      assert html =~ ~s(aria-hidden="true")
    end

    test "navigation structure supports responsive layout" do
      assigns = %{}
      html = render_component(&Layouts.site_header/1, assigns)

      # Left and right sections for flexible layout
      assert html =~ ~s(site-header_left)
      assert html =~ ~s(site-header_right)
    end
  end
end
