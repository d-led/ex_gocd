defmodule ExGoCDWeb.Router do
  use ExGoCDWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExGoCDWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :form do
    plug :accepts, ["html", "json"]
    plug :fetch_session
  end

  scope "/", ExGoCDWeb do
    pipe_through :browser

    live_session :gocd, layout: {ExGoCDWeb.Layouts, :gocd} do
      live "/", DashboardLive, :index
      live "/pipelines", DashboardLive, :index
      live "/agents", AgentsLive, :index
      live "/agents/:uuid/job_run_history", AgentJobHistoryLive, :index
    end
  end

  # Original GoCD agent registration endpoints (backward compatibility)
  scope "/admin", ExGoCDWeb do
    pipe_through :form

    # Agent registration endpoints matching original GoCD API
    post "/agent", AdminAgentController, :register
    get "/agent/token", AdminAgentController, :token
    get "/agent/root_certificate", AdminAgentController, :root_certificate
  end

  # API routes for agents and other resources
  scope "/api", ExGoCDWeb.API do
    pipe_through :api

    # Agent management (matching GoCD's agent API spec)
    post "/agents/register", AgentController, :register
    get "/agents", AgentController, :index
    get "/agents/:uuid", AgentController, :show
    patch "/agents/:uuid", AgentController, :update
    delete "/agents/:uuid", AgentController, :delete
    put "/agents/:uuid/enable", AgentController, :enable
    put "/agents/:uuid/disable", AgentController, :disable
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ex_gocd, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ExGoCDWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
