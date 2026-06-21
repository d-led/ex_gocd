defmodule ExGoCDWeb.Router do
  use ExGoCDWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExGoCDWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug ExGoCDWeb.Plugs.AuthHeaderPlug
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug ExGoCDWeb.Plugs.TokenAuthPlug
    plug ExGoCDWeb.Plugs.GoCDAPIHeaders
  end

  pipeline :form do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :agent_remoting do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :put_secure_browser_headers
  end

  pipeline :files_api do
    # Simple pipeline for raw file transfer without content negotiation or session dependencies
  end

  scope "/", ExGoCDWeb do
    pipe_through :browser

    # Session auth — GoCD-style login/logout
    get "/auth/login", SessionController, :new
    post "/auth/login", SessionController, :create
    delete "/auth/logout", SessionController, :delete

    post "/go/pipelines/:pipeline_name/:counter/:stage_name/run", API.PipelineOperationsController, :approve_stage

    get "/api_json/pipelines/value_stream_map/:pipeline_name/:pipeline_counter", ValueStreamMapController, :show
    get "/api_json/materials/value_stream_map/:material_fingerprint/:revision", ValueStreamMapController, :show_material
    get "/api_json/go/pipelines/value_stream_map/:pipeline_name/:pipeline_counter", ValueStreamMapController, :show
    get "/api_json/go/materials/value_stream_map/:material_fingerprint/:revision", ValueStreamMapController, :show_material

    # CCTray XML feed for CI monitoring tools
    get "/go/cctray.xml", CCTrayController, :index

    live_session :gocd, on_mount: [{ExGoCDWeb.LiveSession, :assign_current_user}] do
      live "/", DashboardLive, :index
      live "/pipelines", DashboardLive, :index
      live "/agents", AgentsLive, :index
      live "/materials", MaterialsLive, :index
      live "/agents/:uuid/job_run_history", AgentJobHistoryLive, :index
      live "/agents/:uuid/job_run_history/:build_id", AgentJobRunDetailLive, :show
      live "/pipelines/value_stream_map/:pipeline_name/:pipeline_counter", ValueStreamMapLive, :show
      live "/materials/value_stream_map/:material_fingerprint/:revision", ValueStreamMapLive, :show_material
      live "/go/pipelines/value_stream_map/:pipeline_name/:pipeline_counter", ValueStreamMapLive, :show
      live "/go/materials/value_stream_map/:material_fingerprint/:revision", ValueStreamMapLive, :show_material
      live "/pipeline/activity/:pipeline_name", PipelineActivityLive, :index
      live "/go/pipeline/activity/:pipeline_name", PipelineActivityLive, :index
      live "/compare/:pipeline_name/:from_counter/with/:to_counter", CompareLive, :show
      live "/go/compare/:pipeline_name/:from_counter/with/:to_counter", CompareLive, :show
      live "/pipelines/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter", StageDetailsLive, :show
      live "/go/pipelines/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter", StageDetailsLive, :show
      live "/tab/build/detail/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name", JobDetailsLive, :show
      live "/go/tab/build/detail/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name", JobDetailsLive, :show

      # Admin Panel routes
      live "/admin", AdminLive, :index
      live "/admin/:tab", AdminLive, :index
      live "/go/admin", AdminLive, :index
      live "/go/admin/:tab", AdminLive, :index

      # Analytics routes (built-in, no external tools required)
      live "/analytics", AnalyticsLive, :index
      live "/analytics/:tab", AnalyticsLive, :index

      # Multi-segment admin paths for GoCD compatibility
      live "/admin/package_repositories/new", AdminLive, :index
      live "/admin/config/server", AdminLive, :index
      live "/admin/security/auth_configs", AdminLive, :index
      live "/admin/security/roles", AdminLive, :index

      live "/go/admin/package_repositories/new", AdminLive, :index
      live "/go/admin/config/server", AdminLive, :index
      live "/go/admin/security/auth_configs", AdminLive, :index
      live "/go/admin/security/roles", AdminLive, :index

      # Pipeline configuration and wizard routes
      live "/admin/pipelines/new", PipelineWizardLive, :new
      live "/go/admin/pipelines/new", PipelineWizardLive, :new
      live "/admin/pipelines/:pipeline_name/edit/*sub_path", PipelineConfigLive, :edit
      live "/go/admin/pipelines/:pipeline_name/edit/*sub_path", PipelineConfigLive, :edit

      # External CI repo wizard
      live "/admin/config_repos/new", ExternalCIRepoWizardLive, :index
      live "/go/admin/config_repos/new", ExternalCIRepoWizardLive, :index
    end
  end

  # Original GoCD agent registration endpoints (backward compatibility)
  scope "/admin", ExGoCDWeb do
    pipe_through :agent_remoting

    # Agent registration endpoints matching original GoCD API
    post "/agent", AdminAgentController, :register
    get "/agent/token", AdminAgentController, :token
    get "/agent/root_certificate", AdminAgentController, :root_certificate
  end

  # API routes for agents and other resources (GoCD spec: api.go.cd)
  # Served at both /api and /go/api for compatibility with GoCD clients.
  scope "/api", ExGoCDWeb.API do
    pipe_through :api

    get "/stats", StatsController, :show
    post "/test/start_agents", TestController, :start_agents
    post "/test/start_http_agents", TestController, :start_http_agents

    # Agent management (matching GoCD's agent API spec)
    post "/agents/register", AgentController, :register
    get "/agents", AgentController, :index
    get "/agents/:uuid", AgentController, :show
    patch "/agents/:uuid", AgentController, :update
    delete "/agents/:uuid", AgentController, :delete
    put "/agents/:uuid/enable", AgentController, :enable
    put "/agents/:uuid/disable", AgentController, :disable

    # Build console log upload (agent streams stdout/stderr here)
    post "/builds/:build_id/console", BuildConsoleController, :append

    # Schedule a job (enqueue for next idle agent; GoCD-style pipeline/stage/job)
    post "/jobs/schedule", JobController, :schedule
    get "/jobs/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name", JobController, :show
    get "/jobs/:pipeline_name/:stage_name/:job_name/history", JobController, :history

    get "/dashboard", DashboardController, :show
    get "/version", VersionController, :show

    # Pipeline operations (pause/unpause/approve/status/unlock/schedule)
    get "/pipelines/:pipeline_name/status", PipelineOperationsController, :status
    post "/pipelines/:pipeline_name/pause", PipelineOperationsController, :pause
    post "/pipelines/:pipeline_name/unpause", PipelineOperationsController, :unpause
    post "/pipelines/:pipeline_name/unlock", PipelineOperationsController, :unlock
    post "/pipelines/:pipeline_name/schedule", PipelineOperationsController, :schedule
    post "/pipelines/:pipeline_name/:counter/:stage_name/run", PipelineOperationsController, :approve_stage

    # SCM post-commit and push webhooks
    post "/admin/materials/git/notify", WebhookController, :git_notify
    post "/webhooks/github/notify", WebhookController, :github_notify
    post "/webhooks/gitlab/notify", WebhookController, :gitlab_notify

    # Pipeline instance history & details
    get "/pipelines/:pipeline_name/history", PipelineInstanceController, :history
    get "/pipelines/:pipeline_name/:counter", PipelineInstanceController, :show

    # Stage instance & operations
    get "/stages/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter", StageController, :show
    get "/stages/:pipeline_name/:stage_name/history", StageController, :history
    post "/stages/:pipeline_name/:pipeline_counter/:stage_name/cancel", StageController, :cancel

    # User management (GoCD users v3)
    get "/users", UserController, :index
    get "/users/:username", UserController, :show
    post "/users", UserController, :create
    patch "/users/:username", UserController, :update
    delete "/users/:username", UserController, :delete

    # Analytics
    get "/analytics", AnalyticsController, :index
    get "/analytics/:type", AnalyticsController, :show
  end

  scope "/api/admin", ExGoCDWeb.API.Admin do
    pipe_through :api

    resources "/pipelines", PipelineConfigController, except: [:new, :edit], param: "name"
    resources "/templates", TemplateController, except: [:new, :edit], param: "name"
    resources "/environments", EnvironmentController, except: [:new, :edit], param: "name"

    get "/maintenance_mode/info", MaintenanceModeController, :show
    post "/maintenance_mode/enable", MaintenanceModeController, :enable
    post "/maintenance_mode/disable", MaintenanceModeController, :disable

    post "/backups", BackupController, :create
  end

  scope "/api/current_user", ExGoCDWeb.API do
    pipe_through :api

    get "/access_tokens", PersonalAccessTokenController, :index
    get "/access_tokens/:id", PersonalAccessTokenController, :show
    post "/access_tokens", PersonalAccessTokenController, :create
    post "/access_tokens/:id/revoke", PersonalAccessTokenController, :revoke
  end

  scope "/go/api/current_user", ExGoCDWeb.API do
    pipe_through :api

    get "/access_tokens", PersonalAccessTokenController, :index
    get "/access_tokens/:id", PersonalAccessTokenController, :show
    post "/access_tokens", PersonalAccessTokenController, :create
    post "/access_tokens/:id/revoke", PersonalAccessTokenController, :revoke
  end

  scope "/go/api", ExGoCDWeb.API do
    pipe_through :api

    get "/stats", StatsController, :show

    post "/agents/register", AgentController, :register
    get "/agents", AgentController, :index
    get "/agents/:uuid", AgentController, :show
    patch "/agents/:uuid", AgentController, :update
    delete "/agents/:uuid", AgentController, :delete
    put "/agents/:uuid/enable", AgentController, :enable
    put "/agents/:uuid/disable", AgentController, :disable
    post "/builds/:build_id/console", BuildConsoleController, :append
    post "/jobs/schedule", JobController, :schedule
    get "/jobs/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name", JobController, :show
    get "/jobs/:pipeline_name/:stage_name/:job_name/history", JobController, :history

    get "/dashboard", DashboardController, :show
    get "/version", VersionController, :show

    # Pipeline operations (pause/unpause/approve/status/unlock/schedule)
    get "/pipelines/:pipeline_name/status", PipelineOperationsController, :status
    post "/pipelines/:pipeline_name/pause", PipelineOperationsController, :pause
    post "/pipelines/:pipeline_name/unpause", PipelineOperationsController, :unpause
    post "/pipelines/:pipeline_name/unlock", PipelineOperationsController, :unlock
    post "/pipelines/:pipeline_name/schedule", PipelineOperationsController, :schedule
    post "/pipelines/:pipeline_name/:counter/:stage_name/run", PipelineOperationsController, :approve_stage

    # SCM post-commit and push webhooks
    post "/admin/materials/git/notify", WebhookController, :git_notify
    post "/webhooks/github/notify", WebhookController, :github_notify
    post "/webhooks/gitlab/notify", WebhookController, :gitlab_notify

    # Pipeline instance history & details
    get "/pipelines/:pipeline_name/history", PipelineInstanceController, :history
    get "/pipelines/:pipeline_name/:counter", PipelineInstanceController, :show

    # Stage instance & operations
    get "/stages/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter", StageController, :show
    get "/stages/:pipeline_name/:stage_name/history", StageController, :history
    post "/stages/:pipeline_name/:pipeline_counter/:stage_name/cancel", StageController, :cancel

    # User management (GoCD users v3)
    get "/users", UserController, :index
    get "/users/:username", UserController, :show
    post "/users", UserController, :create
    patch "/users/:username", UserController, :update
    delete "/users/:username", UserController, :delete
  end

  # GoCD internal agent remoting API (HTTP-based, used by official Go agent)
  # Matches InternalAgentControllerV1.java in GoCD: POST /remoting/api/agent/*
  scope "/remoting/api/agent", ExGoCDWeb do
    pipe_through :api

    post "/ping", AgentRemotingController, :ping
    post "/get_work", AgentRemotingController, :get_work
    post "/get_cookie", AgentRemotingController, :get_cookie
    post "/report_current_status", AgentRemotingController, :report_current_status
    post "/report_completing", AgentRemotingController, :report_completing
    post "/report_completed", AgentRemotingController, :report_completed
    post "/is_ignored", AgentRemotingController, :check_ignored
  end

  scope "/go/remoting/api/agent", ExGoCDWeb do
    pipe_through :api

    post "/ping", AgentRemotingController, :ping
    post "/get_work", AgentRemotingController, :get_work
    post "/get_cookie", AgentRemotingController, :get_cookie
    post "/report_current_status", AgentRemotingController, :report_current_status
    post "/report_completing", AgentRemotingController, :report_completing
    post "/report_completed", AgentRemotingController, :report_completed
    post "/is_ignored", AgentRemotingController, :check_ignored
  end

  # Files/Artifacts API endpoints used by agents and downstream stages
  scope "/files", ExGoCDWeb do
    pipe_through :files_api

    get "/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path", ArtifactsController, :show
    post "/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path", ArtifactsController, :create
    put "/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path", ArtifactsController, :update
  end

  scope "/go/files", ExGoCDWeb do
    pipe_through :files_api

    get "/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path", ArtifactsController, :show
    post "/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path", ArtifactsController, :create
    put "/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path", ArtifactsController, :update
  end

  scope "/remoting/files", ExGoCDWeb do
    pipe_through :files_api

    get "/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path", ArtifactsController, :show
    post "/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path", ArtifactsController, :create
    put "/:pipeline_name/:pipeline_counter/:stage_name/:stage_counter/:job_name/*file_path", ArtifactsController, :update
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
