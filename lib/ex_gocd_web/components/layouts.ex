defmodule ExGoCDWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ExGoCDWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the GoCD site header.

  Pass `is_user_admin` to show/hide admin-only UI (e.g. Admin nav).
  """
  attr :current_path, :string, default: "/"
  attr :is_user_admin, :boolean, default: false
  attr :current_user, :any, default: nil
  attr :open_mode, :boolean, default: true

  def site_header(assigns) do
    ~H"""
    <header class="site-header" role="banner">
      <a
        aria-label="GoCD Logo - Go to Pipelines"
        href="/pipelines"
        class="gocd_logo"
        tabindex="0"
      ></a>
      <button
        class="navbtn"
        aria-label="Open navigation menu"
        aria-expanded="false"
        aria-controls="main-navigation"
        type="button"
      >
        <div class="bar" aria-hidden="true"></div>
      </button>
      <nav id="main-navigation" class="main-navigation" role="navigation" aria-label="Main navigation">
        <div class="site-header_left">
          <ul class="site-navigation_left" role="menubar">
            <li role="none" class={if active_tab?(assigns, :dashboard), do: "active", else: ""}>
              <a
                href="/pipelines"
                role="menuitem"
                tabindex="0"
                aria-current={if active_tab?(assigns, :dashboard), do: "page", else: "false"}
              >
                Dashboard
              </a>
            </li>
            <li role="none" class={if active_tab?(assigns, :agents), do: "active", else: ""}>
              <a
                href="/agents"
                role="menuitem"
                tabindex="0"
                aria-current={if active_tab?(assigns, :agents), do: "page", else: "false"}
              >
                Agents
              </a>
            </li>
            <li role="none" class={if active_tab?(assigns, :materials), do: "active", else: ""}>
              <a
                href="/materials"
                role="menuitem"
                tabindex="0"
                aria-current={if active_tab?(assigns, :materials), do: "page", else: "false"}
              >
                Materials
              </a>
            </li>
            <li role="none" class={if active_tab?(assigns, :analytics), do: "active", else: ""}>
              <a
                href="/analytics"
                role="menuitem"
                tabindex="0"
                aria-current={if active_tab?(assigns, :analytics), do: "page", else: "false"}
              >
                Analytics
              </a>
            </li>
            <%= if @is_user_admin do %>
              <li
                role="none"
                class={
                  if active_tab?(assigns, :admin), do: "active is-drop-down", else: "is-drop-down"
                }
              >
                <a
                  href="/admin"
                  role="menuitem"
                  tabindex="0"
                  aria-current={if active_tab?(assigns, :admin), do: "page", else: "false"}
                >
                  Admin <i class="fa fa-caret-down caret-down-icon"></i>
                </a>
                <div class="sub-navigation" phx-update="ignore" id="admin-sub-navigation">
                  <ul class="site-sub-nav">
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin"), do: "is-active")
                        ]}
                      >
                        Overview
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/pipelines"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/pipelines"), do: "is-active")
                        ]}
                      >
                        Pipelines
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/environments"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/environments"), do: "is-active")
                        ]}
                      >
                        Environments
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/templates"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/templates"), do: "is-active")
                        ]}
                      >
                        Templates
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/config_xml"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/config_xml"), do: "is-active")
                        ]}
                      >
                        Config XML
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/package_repositories/new"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/package_repositories/new"),
                            do: "is-active"
                          )
                        ]}
                      >
                        Package Repositories
                      </a>
                    </li>
                  </ul>
                  <ul class="site-sub-nav">
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/elastic_agents"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/elastic_agents"),
                            do: "is-active"
                          )
                        ]}
                      >
                        Elastic Agents
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/config_repos"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/config_repos"), do: "is-active")
                        ]}
                      >
                        Config Repositories
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/artifact_stores"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/artifact_stores"),
                            do: "is-active"
                          )
                        ]}
                      >
                        Artifact Stores
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/secret_configs"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/secret_configs"), do: "is-active")
                        ]}
                      >
                        Secret Management
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/scms"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/scms"), do: "is-active")
                        ]}
                      >
                        Pluggable SCMs
                      </a>
                    </li>
                  </ul>
                  <ul class="site-sub-nav">
                    <li class="site-sub-nav_heading">Server configuration</li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/config/server"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/config/server"), do: "is-active")
                        ]}
                      >
                        Server Configuration
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/maintenance_mode"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/maintenance_mode"),
                            do: "is-active"
                          )
                        ]}
                      >
                        Server Maintenance Mode
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/backup"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/backup"), do: "is-active")
                        ]}
                      >
                        Backup
                      </a>
                    </li>
                  </ul>
                  <ul class="site-sub-nav">
                    <li class="site-sub-nav_heading">Security</li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/security/auth_configs"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/security/auth_configs"),
                            do: "is-active"
                          )
                        ]}
                      >
                        Authorization Configuration
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/security/roles"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/security/roles"), do: "is-active")
                        ]}
                      >
                        Role configuration
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/users"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/users"), do: "is-active")
                        ]}
                      >
                        Users Management
                      </a>
                    </li>
                    <li class="site-sub-nav_item">
                      <a
                        href="/admin/admin_access_tokens"
                        class={[
                          "site-sub-nav_link",
                          if(active_sub_nav?(@current_path, "/admin/admin_access_tokens"),
                            do: "is-active"
                          )
                        ]}
                      >
                        Access Tokens Management
                      </a>
                    </li>
                  </ul>
                </div>
              </li>
            <% end %>
          </ul>
        </div>
        <div class="site-header_right" style="display:flex;align-items:center;gap:16px">
          <a
            class="need_help"
            href="https://github.com/d-led/ex_gocd"
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Need Help? Opens in new window"
          >
            Need Help?
          </a>
          <div style="display:flex;align-items:center;gap:8px;font-size:12px;color:rgba(255,255,255,0.7)">
            <%= if @current_user && @current_user.username != "guest" do %>
              <span style="color:rgba(255,255,255,0.9);font-weight:600">
                {@current_user.display_name || @current_user.username}
              </span>
              <form method="POST" action="/auth/logout" style="display:inline;margin:0">
                <input type="hidden" name="_method" value="delete" />
                <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
                <button
                  type="submit"
                  style="background:rgba(255,255,255,0.1);border:1px solid rgba(255,255,255,0.2);color:rgba(255,255,255,0.8);padding:3px 10px;border-radius:3px;font-size:11px;cursor:pointer"
                  aria-label="Sign out"
                >
                  Sign out
                </button>
              </form>
            <% else %>
              <%= if not @open_mode do %>
                <a
                  href="/auth/login"
                  style="background:rgba(255,255,255,0.12);border:1px solid rgba(255,255,255,0.2);color:rgba(255,255,255,0.85);padding:3px 10px;border-radius:3px;font-size:11px;text-decoration:none"
                  aria-label="Sign in"
                >
                  Sign in
                </a>
              <% end %>
            <% end %>
          </div>
        </div>
      </nav>
    </header>
    """
  end

  @spec active_tab?(map(), :dashboard | :agents | :materials | :admin) :: boolean()
  defp active_tab?(assigns, tab) do
    current_path = Map.get(assigns, :current_path, "")

    case tab do
      :dashboard ->
        current_path in ["/", "/pipelines", "/go/pipelines"]

      :agents ->
        String.starts_with?(current_path, "/agents") or
          String.starts_with?(current_path, "/go/agents")

      :materials ->
        String.starts_with?(current_path, "/materials") or
          String.starts_with?(current_path, "/go/materials")

      :analytics ->
        String.starts_with?(current_path, "/analytics")

      :admin ->
        String.starts_with?(current_path, "/admin") or
          String.starts_with?(current_path, "/go/admin")
    end
  end

  defp active_sub_nav?(current_path, path) do
    norm_current = String.replace(current_path, ~r"^/go", "")
    norm_path = String.replace(path, ~r"^/go", "")

    norm_current == norm_path
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
