defmodule RegionalAffinityWeb.Router do
  use RegionalAffinityWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RegionalAffinityWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RegionalAffinityWeb do
    pipe_through :browser

    live "/", PluginDashboardLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", RegionalAffinityWeb do
  #   pipe_through :api
  # end
end
