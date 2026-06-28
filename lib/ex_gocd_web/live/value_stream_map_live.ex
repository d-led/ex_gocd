defmodule ExGoCDWeb.ValueStreamMapLive do
  @moduledoc """
  LiveView for the Value Stream Map (VSM) page.
  Renders interactive dependency graphs for pipeline instances and SCM materials.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.Pipelines.ValueStreamMap

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      cond do
        Map.has_key?(params, "pipeline_name") ->
          name = params["pipeline_name"]
          counter = String.to_integer(params["pipeline_counter"])

          case ValueStreamMap.get_pipeline_vsm(name, counter) do
            {:ok, vsm} ->
              socket
              |> assign(:vsm, vsm)
              |> assign(:type, :pipeline)
              |> assign(:title, "Value Stream Map of #{name}")
              |> assign(:entity_label, "Pipeline")
              |> assign(:entity_name, name)
              |> assign(:entity_counter_label, "Instance")
              |> assign(:entity_counter, to_string(counter))
              |> assign(:entity_locator, "/pipelines?search=#{name}")

            _ ->
              socket
              |> put_flash(:error, "Value Stream Map not found.")
              |> redirect(to: "/pipelines")
          end

        Map.has_key?(params, "material_fingerprint") ->
          fingerprint = params["material_fingerprint"]
          revision = params["revision"]

          {:ok, vsm} = ValueStreamMap.get_material_vsm(fingerprint, revision)

          material_name =
            vsm
            |> Map.get("levels", [])
            |> List.first(%{})
            |> Map.get("nodes", [])
            |> List.first(%{})
            |> Map.get("name")

          socket
          |> assign(:vsm, vsm)
          |> assign(:type, :material)
          |> assign(:title, "Value Stream Map of #{Path.basename(material_name || "")}")
          |> assign(:entity_label, "Material")
          |> assign(:entity_name, material_name)
          |> assign(:entity_counter_label, "Revision")
          |> assign(:entity_counter, String.slice(revision, 0, 12))
          |> assign(:entity_locator, "/materials?search=#{String.slice(revision, 0, 8)}")
      end

    {:noreply, socket}
  end

  defp current?(node, vsm) do
    node["id"] == vsm["current_pipeline"] or node["id"] == vsm["current_material"]
  end

  alias ExGoCD.StageStatus

  defp stage_status_bg(status) do
    StageStatus.stage_bg(status)
  end

  defp pipeline_node_status(node) do
    inst = (node["instances"] || []) |> List.first()
    if is_nil(inst), do: nil, else: do_pipeline_node_status(inst)
  end

  defp do_pipeline_node_status(inst) do
    stages = inst["stages"] || []
    StageStatus.pipeline_status(Enum.map(stages, & &1["status"]))
  end

  defp node_status_border(status) do
    StageStatus.node_border(status)
  end

  defp node_status_badge(status) do
    StageStatus.node_badge(status)
  end

  # ── Material type icon helpers ──────────────────────────────────────────

  defp material_icon("git"), do: "fa-brands fa-git"
  defp material_icon("hg"), do: "fa-solid fa-code-fork"
  defp material_icon("svn"), do: "fa-solid fa-database"
  defp material_icon("p4"), do: "fa-solid fa-terminal"
  defp material_icon("tfs"), do: "fa-brands fa-windows"
  defp material_icon("dependency"), do: "fa-solid fa-diagram-project"
  defp material_icon("package"), do: "fa-solid fa-box"
  defp material_icon("plugin"), do: "fa-solid fa-plug"
  defp material_icon("pluggable_scm"), do: "fa-solid fa-plug"
  defp material_icon(_), do: "fa-solid fa-code-branch"

  defp material_icon_bg("dependency"), do: "bg-purple-50 text-purple-600"
  defp material_icon_bg("package"), do: "bg-amber-50 text-amber-600"
  defp material_icon_bg(_), do: "bg-orange-50 text-orange-600"

  defp material_label_color("dependency"), do: "text-purple-600"
  defp material_label_color("package"), do: "text-amber-600"
  defp material_label_color(_), do: "text-orange-600"

  # ── Node widget ─────────────────────────────────────────────────────────

  defp vsm_node_widget(assigns) do
    ~H"""
    <% p_status = if @node["node_type"] == "PIPELINE", do: pipeline_node_status(@node), else: nil

    current_overrides =
      if @is_current,
        do: "border-[#943a9e] border-2 ring-4 ring-purple-100",
        else: node_status_border(p_status) %>
    <div
      id={"node-#{@node["id"]}"}
      data-id={@node["id"]}
      data-parents={Jason.encode!(@node["parents"] || [])}
      data-dependents={Jason.encode!(@node["dependents"] || [])}
      class={"vsm-node p-3 md:p-4 border rounded shadow-sm w-64 md:w-72 flex flex-col justify-between transition-all duration-200 bg-white relative z-10 pointer-events-auto " <> current_overrides <> if(!@is_current && p_status, do: " hover:shadow-md", else: "")}
    >
      <%= if @is_current do %>
        <div class="absolute -top-3 -right-2 text-[#943a9e] bg-white rounded-full">
          <i class="fa-solid fa-circle-check text-xl"></i>
        </div>
      <% end %>

      <div class="flex items-start justify-between">
        <div class="flex items-center gap-2.5">
          <%= if @node["node_type"] == "MATERIAL" do %>
            <% mat_type = Map.get(@node, "material_type") || "git" %>
            <div class={"rounded p-1.5 flex items-center justify-center w-8 h-8 flex-shrink-0 " <> material_icon_bg(mat_type)}>
              <i class={material_icon(mat_type) <> " text-lg"}></i>
            </div>
            <div class="flex flex-col min-w-0">
              <span class={"text-[9px] font-bold uppercase tracking-wider " <> material_label_color(mat_type)}>
                Material
              </span>
              <span class="text-xs font-semibold text-gray-700 truncate w-40" title={@node["name"]}>
                {Path.basename(@node["name"] || "")}
              </span>
            </div>
          <% else %>
            <div class="bg-cyan-50 text-cyan-600 rounded p-1.5 flex items-center justify-center w-8 h-8 flex-shrink-0">
              <i class="fa-solid fa-network-wired text-lg"></i>
            </div>
            <div class="flex flex-col min-w-0">
              <span class="text-[9px] text-cyan-600 font-bold uppercase tracking-wider">
                Pipeline
              </span>
              <.link
                navigate={~p"/pipelines?search=#{@node["name"]}"}
                class="text-xs font-semibold text-[#2d6ca2] hover:underline truncate w-40"
                title={@node["name"]}
              >
                {@node["name"]}
              </.link>
            </div>
          <% end %>
        </div>

        <div class="flex items-center gap-1">
          <%= if @is_current do %>
            <span class="text-[9px] bg-purple-100 text-[#943a9e] font-extrabold px-1.5 py-0.5 rounded uppercase font-mono">
              Current
            </span>
          <% end %>
          <%= if p_status do %>
            <span class={"text-[9px] font-bold px-1.5 py-0.5 rounded uppercase font-mono " <> node_status_badge(p_status)}>
              {p_status}
            </span>
          <% end %>
          <%= if @node["fan_in"] && @node["fan_in"] > 1 do %>
            <span
              class="text-[9px] bg-amber-100 text-amber-700 font-bold px-1.5 py-0.5 rounded uppercase font-mono"
              title="Multiple upstreams converge here"
            >
              {"FI:"}{@node["fan_in"]}
            </span>
          <% end %>
          <%= if @node["fan_out"] && @node["fan_out"] > 1 do %>
            <span
              class="text-[9px] bg-blue-100 text-blue-700 font-bold px-1.5 py-0.5 rounded uppercase font-mono"
              title="Multiple downstreams diverge here"
            >
              {"FO:"}{@node["fan_out"]}
            </span>
          <% end %>
        </div>
      </div>

      <div class="mt-3 border-t border-gray-100 pt-2.5">
        <%= if @node["node_type"] == "MATERIAL" do %>
          <%= for rev <- @node["material_revisions"] || [] do %>
            <%= for mod <- rev["modifications"] || [] do %>
              <div class="flex flex-col text-xs text-gray-500 gap-1">
                <div class="flex items-center justify-between">
                  <span class="font-bold text-gray-700 truncate max-w-[180px]" title={mod["user"]}>
                    {mod["user"]}
                  </span>
                  <.link navigate={mod["locator"]} class="font-mono text-cyan-600 hover:underline">
                    {String.slice(mod["revision"], 0, 8)}
                  </.link>
                </div>
                <p class="text-gray-600 italic line-clamp-2 mt-0.5 font-medium">"{mod["comment"]}"</p>
                <span class="text-[9px] text-gray-400 font-medium mt-0.5">
                  {mod["modified_time"]}
                </span>
              </div>
            <% end %>
          <% end %>
        <% else %>
          <%= for inst <- @node["instances"] || [] do %>
            <div class="flex flex-col gap-2">
              <div class="flex justify-between items-center text-xs">
                <span class="font-mono text-gray-600 font-bold">Instance: {inst["label"]}</span>
                <.link navigate={inst["locator"]} class="text-cyan-600 hover:underline font-bold">
                  VSM
                </.link>
              </div>

              <ul class="flex flex-wrap gap-1 mt-1">
                <%= for stage <- inst["stages"] || [] do %>
                  <li class="relative">
                    <.link
                      navigate={stage["locator"]}
                      class={"w-6 h-6 block rounded-sm transition-transform hover:scale-110 " <> stage_status_bg(stage["status"])}
                      title={"#{stage["name"]} (#{stage["status"]})"}
                      aria-label={"#{stage["name"]} (#{stage["status"]})"}
                    ></.link>
                  </li>
                <% end %>
              </ul>

              <%= if ti = inst["trigger_info"] do %>
                <div class="mt-1.5 pt-1.5 border-t border-dashed border-gray-200">
                  <span class="text-[9px] text-gray-400 uppercase tracking-wider font-bold">
                    Trigger
                  </span>
                  <div class="text-[10px] text-gray-600 mt-0.5 flex flex-col gap-0.5">
                    <span>
                      <i class="fa-solid fa-user text-gray-400 mr-1 w-3"></i>
                      {ti["triggered_by"]}
                    </span>
                    <%= if ti["triggered_at"] do %>
                      <span>
                        <i class="fa-solid fa-clock text-gray-400 mr-1 w-3"></i>
                        {ti["triggered_at"]}
                      </span>
                    <% end %>
                    <%= for mat <- ti["materials"] || [] do %>
                      <span class="truncate" title={"#{mat["type"]}: #{mat["url"]}"}>
                        <i class="fa-solid fa-code-branch text-gray-400 mr-1 w-3"></i>
                        {String.slice(mat["url"] || "", 0, 30)}
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="vsm-page px-4 md:px-8 py-4 md:py-8 bg-[#f4f8f9] min-h-screen">
      <div class="page-header flex flex-col gap-2 border-b border-gray-200 pb-4 mb-6">
        <%!-- Breadcrumbs --%>
        <div class="flex items-center gap-2 text-xs text-gray-500 font-mono font-bold uppercase tracking-wider flex-wrap">
          <.link navigate={~p"/pipelines"} class="text-[#2d6ca2] hover:underline">Pipelines</.link>
          <span>/</span>
          <%= if @type == :pipeline do %>
            <.link
              navigate={~p"/pipeline/activity/#{@entity_name}"}
              class="text-[#2d6ca2] hover:underline"
            >
              {@entity_name}
            </.link>
            <span>/</span>
            <span class="text-gray-900">{@entity_counter}</span>
            <span>/</span>
            <span class="text-gray-900">VSM</span>
          <% else %>
            <.link navigate={~p"/materials"} class="text-[#2d6ca2] hover:underline">Materials</.link>
            <span>/</span>
            <span class="text-gray-900 truncate max-w-[200px]">{@entity_name}</span>
            <span>/</span>
            <span class="text-gray-900">VSM</span>
          <% end %>
        </div>

        <div class="flex items-baseline gap-4">
          <span class="text-[10px] uppercase tracking-wider text-gray-500 font-bold font-mono">
            {@entity_label}
          </span>
          <h1 class="text-lg md:text-xl font-extrabold text-gray-900 font-mono">{@entity_name}</h1>
          <span class="text-[10px] uppercase tracking-wider text-gray-500 font-bold font-mono">
            {@entity_counter_label}
          </span>
          <h2 class="text-lg md:text-xl font-extrabold text-gray-700 font-mono">{@entity_counter}</h2>
        </div>
      </div>

      <div
        id="vsm-container"
        phx-hook="VSMGraph"
        phx-update="ignore"
        class="vsm-container-wrapper relative border border-gray-200 rounded-lg p-4 md:p-10 bg-white shadow-sm overflow-x-auto md:overflow-hidden min-h-[400px] md:min-h-[500px]"
      >
        <%!-- Zoom controls — visible only on desktop (hidden on mobile) --%>
        <div class="vsm-zoom-controls hidden md:flex absolute top-3 right-3 z-30 gap-1">
          <button
            id="vsm-zoom-out"
            class="w-8 h-8 flex items-center justify-center rounded bg-white border border-gray-300 text-gray-600 hover:bg-gray-100 hover:border-gray-400 transition-colors shadow-sm"
            title="Zoom out"
            aria-label="Zoom out"
          >
            <i class="fa-solid fa-minus text-xs"></i>
          </button>
          <button
            id="vsm-zoom-in"
            class="w-8 h-8 flex items-center justify-center rounded bg-white border border-gray-300 text-gray-600 hover:bg-gray-100 hover:border-gray-400 transition-colors shadow-sm"
            title="Zoom in"
            aria-label="Zoom in"
          >
            <i class="fa-solid fa-plus text-xs"></i>
          </button>
          <button
            id="vsm-zoom-fit"
            class="flex items-center justify-center rounded bg-white border border-gray-300 text-gray-600 hover:bg-gray-100 hover:border-gray-400 transition-colors shadow-sm px-2 py-1 text-xs font-medium gap-1"
            title="Fit to screen"
            aria-label="Fit to screen"
          >
            <i class="fa-solid fa-expand text-[10px]"></i>
            <span class="hidden sm:inline">Fit</span>
          </button>
        </div>

        <%!-- Transform group: SVG and content nodes move/scale together --%>
        <div
          id="vsm-transform-group"
          class="vsm-transform-group relative"
          style="transform-origin: 0 0;"
        >
          <svg
            id="vsm-svg"
            class="absolute top-0 left-0"
            style="z-index: 10; overflow: visible;"
          >
            <defs>
              <marker
                id="arrow"
                viewBox="0 0 10 10"
                refX="8"
                refY="5"
                markerWidth="8"
                markerHeight="8"
                orient="auto"
              >
                <path d="M 0 1.5 L 8 5 L 0 8.5 z" fill="#2fa8b6" />
              </marker>
              <marker
                id="arrow-current"
                viewBox="0 0 10 10"
                refX="8"
                refY="5"
                markerWidth="8"
                markerHeight="8"
                orient="auto"
              >
                <path d="M 0 1.5 L 8 5 L 0 8.5 z" fill="#943a9e" />
              </marker>
            </defs>
          </svg>

          <div class="flex flex-col md:flex-row justify-center items-center md:items-stretch gap-8 md:gap-16 min-w-0 md:min-w-[800px] relative z-20 pointer-events-none">
            <%= for level <- @vsm["levels"] do %>
              <div class="vsm-level flex flex-col justify-center gap-10 relative">
                <%= for node <- level["nodes"] do %>
                  <.vsm_node_widget node={node} is_current={current?(node, @vsm)} />
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
