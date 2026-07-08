defmodule ExGoCDWeb.AdminOtelLive do
  @moduledoc """
  Admin page for OpenTelemetry observability status.

  Shows:
  - SDK state (enabled/disabled)
  - Exporter configuration (none, OTLP)
  - Collector reachability health check
  - Instrumentation handler status (Phoenix, Ecto, Process propagator)
  - Environment variables affecting OTel
  - Setup guide for enabling OTel in dev/prod

  Auto-refreshes every 30 seconds to show current collector status.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.Otel.Admin

  @impl true
  def mount(_params, _session, socket) do
    unless socket.assigns[:is_user_admin] do
      {:ok,
       socket
       |> put_flash(:error, "You do not have administration permissions.")
       |> redirect(to: "/")}
    else
      if connected?(socket) do
        :timer.send_interval(30_000, self(), :refresh)
      end

      {:ok,
       socket
       |> assign(:page_title, "GoCD Administration - Observability")
       |> assign(:current_path, "/admin/observability")
       |> refresh_status()}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, refresh_status(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, refresh_status(socket)}
  end

  # -- private ----------------------------------------------------------------

  defp refresh_status(socket) do
    assign(socket, :status, Admin.status())
  end

  # -- render ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-page-wrapper min-h-screen bg-[#f4f8f9] text-[#333] font-sans pb-12">
      <!-- Page Header -->
      <div class="bg-white border-b border-[#e9edef] px-6 py-4 flex justify-between items-center">
        <div class="flex items-center gap-2">
          <h1 class="text-xl font-semibold text-[#333] uppercase tracking-wide">
            Observability
          </h1>
          <a
            href="https://github.com/d-led/ex_gocd"
            target="_blank"
            class="text-[#943a9e] text-base hover:text-purple-800"
            aria-label="Help"
          >
            <i class="fa-solid fa-circle-question"></i>
          </a>
        </div>
        <div class="flex items-center gap-4">
          <span class="text-[10px] text-slate-400">
            Auto-refreshes every 30s
          </span>
          <button
            phx-click="refresh"
            class="px-3 py-1.5 bg-white border border-[#943a9e] text-[#943a9e] rounded text-xs font-semibold hover:bg-purple-50 transition-all"
          >
            <i class="fa fa-sync mr-1"></i> Refresh Now
          </button>
        </div>
      </div>

      <div class="max-w-[1400px] mx-auto px-6 py-6 space-y-6">
        <!-- Status Overview Cards -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
          <.status_card
            icon="fa-satellite-dish"
            title="SDK Status"
            value={if @status.sdk_enabled, do: "Enabled", else: "Disabled"}
            sub={if @status.no_otel_env, do: "Disabled by EX_GOCD_NO_OTEL=1", else: nil}
            status={if @status.sdk_enabled, do: :ok, else: :warn}
          />
          <.status_card
            icon="fa-paper-plane"
            title="Exporter"
            value={exporter_label(@status.exporter)}
            sub={"Service: #{@status.service_name}"}
            status={if @status.exporter == :otlp, do: :ok, else: :neutral}
          />
          <.status_card
            icon="fa-plug"
            title="Collector"
            value={collector_label(@status.collector_reachable)}
            sub={@status.otlp_endpoint}
            status={collector_status(@status.collector_reachable)}
          />
          <.status_card
            icon="fa-code-branch"
            title="Instrumentation"
            value={instrumentation_summary(@status)}
            sub={instrumentation_sub(@status)}
            status={instrumentation_overall(@status)}
          />
        </div>
        
    <!-- Config Source Hint -->
        <div class={[
          "border rounded p-4 text-xs flex items-start gap-3",
          if(@status.sdk_enabled,
            do: "bg-emerald-50 border-emerald-200 text-emerald-800",
            else: "bg-amber-50 border-amber-200 text-amber-800"
          )
        ]}>
          <i class={[
            "fa mt-0.5",
            if(@status.sdk_enabled, do: "fa-circle-info text-emerald-500", else: "fa-triangle-exclamation text-amber-500")
          ]}></i>
          <div>
            <span class="font-bold">Why this state?</span>
            <span class="ml-1">{@status.config_source}</span>
          </div>
        </div>

    <!-- Two-column detail panels -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- Instrumentation Details -->
          <.panel title="Instrumentation Handlers" icon="fa-code-branch">
            <div class="space-y-3">
              <.instrumentation_row
                label="Phoenix (HTTP spans)"
                active={@status.instrumentation.phoenix}
              />
              <.instrumentation_row
                label="Ecto (DB query spans)"
                active={@status.instrumentation.ecto}
              />
              <.instrumentation_row
                label="Process Propagator (cross-node tracing)"
                active={@status.instrumentation.process_propagator}
              />
            </div>
          </.panel>
          
    <!-- Environment Variables -->
          <.panel title="Environment Variables" icon="fa-gear">
            <div class="space-y-3">
              <%= for {var, val} <- @status.env_vars do %>
                <div class="flex justify-between items-center py-2 border-b border-[#e9edef] last:border-0">
                  <code class="text-[11px] font-mono text-slate-600 bg-slate-50 px-2 py-0.5 rounded">
                    {var}
                  </code>
                  <code class={[
                    "text-[11px] font-mono px-2 py-0.5 rounded",
                    if(val == "not set",
                      do: "text-slate-400 bg-transparent",
                      else: "text-slate-700 bg-slate-50"
                    )
                  ]}>
                    {val}
                  </code>
                </div>
              <% end %>
            </div>
          </.panel>
          
    <!-- OTLP Configuration -->
          <.panel title="Exporter Configuration" icon="fa-paper-plane">
            <div class="space-y-4">
              <div class="flex justify-between items-center">
                <span class="text-xs text-slate-500">Exporter type</span>
                <span class={[
                  "text-xs font-bold px-2 py-0.5 rounded",
                  if(@status.exporter == :otlp,
                    do: "bg-emerald-50 text-emerald-600",
                    else: "bg-slate-100 text-slate-500"
                  )
                ]}>
                  {exporter_label(@status.exporter)}
                </span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-xs text-slate-500">OTLP endpoint</span>
                <code class="text-[11px] font-mono text-slate-700 bg-slate-50 px-2 py-0.5 rounded">
                  {@status.otlp_endpoint}
                </code>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-xs text-slate-500">Service name</span>
                <code class="text-[11px] font-mono text-slate-700 bg-slate-50 px-2 py-0.5 rounded">
                  {@status.service_name}
                </code>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-xs text-slate-500">EX_GOCD_NO_OTEL</span>
                <span class={[
                  "text-xs font-bold px-2 py-0.5 rounded",
                  if(@status.no_otel_env,
                    do: "bg-red-50 text-red-600",
                    else: "bg-emerald-50 text-emerald-600"
                  )
                ]}>
                  {if @status.no_otel_env, do: "Set (disabled)", else: "Not set"}
                </span>
              </div>
            </div>
          </.panel>
          
    <!-- Setup Guide -->
          <.panel title="Setup Guide" icon="fa-book">
            <div class="space-y-4 text-xs text-slate-600 leading-relaxed">
              <div>
                <h4 class="font-bold text-slate-700 mb-1">Enabling in Development</h4>
                <p>
                  OTel is enabled by default in <code class="bg-slate-50 px-1 rounded">config/dev.exs</code>.
                  Start the collector and Jaeger:
                </p>
                <pre class="mt-2 bg-slate-50 border border-[#d6e0e2] rounded p-3 text-[11px] font-mono text-slate-700">
                  docker compose up -d jaeger otel-collector
                </pre>
                <p class="mt-2">
                  Traces flow: <strong>ex_gocd → OTLP (localhost:4318) → Collector → Jaeger</strong>
                  <br /> Jaeger UI:
                  <a
                    href="http://localhost:16686/search"
                    target="_blank"
                    class="text-[#943a9e] hover:underline"
                  >
                    http://localhost:16686/search
                  </a>
                </p>
              </div>

              <div class="border-t border-[#e9edef] pt-4">
                <h4 class="font-bold text-slate-700 mb-1">Disabling OTel</h4>
                <p>
                  Set the environment variable to disable all tracing:
                </p>
                <pre class="mt-2 bg-slate-50 border border-[#d6e0e2] rounded p-3 text-[11px] font-mono text-slate-700">
                  EX_GOCD_NO_OTEL=1 mix phx.server
                </pre>
              </div>

              <div class="border-t border-[#e9edef] pt-4">
                <h4 class="font-bold text-slate-700 mb-1">Production Setup</h4>
                <p>
                  In production, configure the OTLP endpoint via environment variables in <code class="bg-slate-50 px-1 rounded">config/runtime.exs</code>:
                </p>
                <pre class="mt-2 bg-slate-50 border border-[#d6e0e2] rounded p-3 text-[11px] font-mono text-slate-700"><%="OTEL_TRACES_EXPORTER=otlp\nOTEL_EXPORTER_OTLP_ENDPOINT=https://your-collector:4318\nOTEL_SERVICE_NAME=ex_gocd_prod"%></pre>
              </div>
            </div>
          </.panel>
        </div>
      </div>
    </div>
    """
  end

  # -- sub-components -------------------------------------------------------

  defp status_card(assigns) do
    ~H"""
    <div class="bg-white rounded border border-[#d6e0e2] p-5 flex items-center gap-4 shadow-sm">
      <div class={[
        "w-12 h-12 rounded flex items-center justify-center shrink-0",
        case @status do
          :ok -> "bg-emerald-50"
          :warn -> "bg-amber-50"
          :neutral -> "bg-slate-100"
          :error -> "bg-red-50"
        end
      ]}>
        <i class={[
          "fa text-xl",
          @icon,
          case @status do
            :ok -> "text-emerald-500"
            :warn -> "text-amber-500"
            :neutral -> "text-slate-400"
            :error -> "text-red-500"
          end
        ]}>
        </i>
      </div>
      <div>
        <p class="text-[10px] text-slate-400 font-bold uppercase tracking-wider">{@title}</p>
        <p class="text-xl font-bold mt-1 text-[#333]">{@value}</p>
        <p :if={@sub} class="text-xs text-slate-500 mt-0.5">{@sub}</p>
      </div>
    </div>
    """
  end

  defp panel(assigns) do
    ~H"""
    <div class="bg-white rounded border border-[#d6e0e2] p-5 shadow-sm">
      <h3 class="text-sm font-bold border-b border-[#e9edef] pb-3 flex items-center gap-2 text-slate-700">
        <i class={["fa text-[#943a9e]", @icon]}></i> {@title}
      </h3>
      <div class="mt-4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp instrumentation_row(assigns) do
    ~H"""
    <div class="flex justify-between items-center py-2 border-b border-[#e9edef] last:border-0">
      <span class="text-xs text-slate-600">{@label}</span>
      <span class={[
        "inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-bold",
        if(@active,
          do: "bg-emerald-50 text-emerald-600 border border-emerald-200",
          else: "bg-slate-50 text-slate-400 border border-[#d6e0e2]"
        )
      ]}>
        <span class={[
          "w-1.5 h-1.5 rounded-full",
          if(@active, do: "bg-emerald-500", else: "bg-slate-300")
        ]}>
        </span>
        {if @active, do: "Active", else: "Inactive"}
      </span>
    </div>
    """
  end

  # -- helpers ---------------------------------------------------------------

  defp exporter_label(:otlp), do: "OTLP"
  defp exporter_label(:none), do: "None (disabled)"
  defp exporter_label(other), do: to_string(other)

  defp collector_label(:reachable), do: "Reachable"
  defp collector_label(:unreachable), do: "Unreachable"
  defp collector_label(:disabled), do: "N/A (disabled)"
  defp collector_label(:not_configured), do: "Not configured"

  defp collector_status(:reachable), do: :ok
  defp collector_status(:unreachable), do: :error
  defp collector_status(_), do: :neutral

  defp instrumentation_summary(%{sdk_enabled: false}) do
    "N/A"
  end

  defp instrumentation_summary(%{instrumentation: %{phoenix: p, ecto: e, process_propagator: pp}}) do
    active = Enum.count([p, e, pp], & &1)
    "#{active}/3 active"
  end

  defp instrumentation_sub(%{sdk_enabled: false}) do
    "SDK disabled — handlers not attached"
  end

  defp instrumentation_sub(%{instrumentation: %{phoenix: p, ecto: e, process_propagator: pp}}) do
    parts =
      []
      |> maybe_add(p, "Phoenix")
      |> maybe_add(e, "Ecto")
      |> maybe_add(pp, "Process")
      |> Enum.join(", ")

    if parts == "", do: "None active", else: parts
  end

  defp maybe_add(acc, true, label), do: acc ++ [label]
  defp maybe_add(acc, false, _label), do: acc

  defp instrumentation_overall(%{sdk_enabled: false}) do
    :neutral
  end

  defp instrumentation_overall(%{instrumentation: %{phoenix: p, ecto: e}}) do
    if p and e, do: :ok, else: :warn
  end
end
