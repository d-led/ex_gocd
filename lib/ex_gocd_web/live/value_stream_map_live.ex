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
          case ValueStreamMap.get_material_vsm(fingerprint, revision) do
            {:ok, vsm} ->
              material_name =
                case hd(hd(vsm["levels"])["nodes"]) do
                  node -> node["name"]
                end
              socket
              |> assign(:vsm, vsm)
              |> assign(:type, :material)
              |> assign(:title, "Value Stream Map of #{Path.basename(material_name || "")}")
              |> assign(:entity_label, "Material")
              |> assign(:entity_name, material_name)
              |> assign(:entity_counter_label, "Revision")
              |> assign(:entity_counter, String.slice(revision, 0, 12))
              |> assign(:entity_locator, "/materials?search=#{String.slice(revision, 0, 8)}")
            _ ->
              socket
              |> put_flash(:error, "Value Stream Map not found.")
              |> redirect(to: "/materials")
          end
      end

    {:noreply, socket}
  end

  defp is_current?(node, vsm) do
    node["id"] == vsm["current_pipeline"] or node["id"] == vsm["current_material"]
  end

  defp stage_status_bg(status) do
    case status do
      "Passed" -> "bg-[#5cb85c]"
      "Failed" -> "bg-[#d9534f]"
      "Building" -> "bg-[#5bc0de]"
      "Cancelled" -> "bg-[#f0ad4e]"
      _ -> "bg-gray-300"
    end
  end

  defp vsm_node_widget(assigns) do
    ~H"""
    <div
      id={"node-#{@node["id"]}"}
      data-id={@node["id"]}
      data-parents={Jason.encode!(@node["parents"] || [])}
      data-dependents={Jason.encode!(@node["dependents"] || [])}
      class={"vsm-node p-4 border rounded shadow-sm w-72 flex flex-col justify-between transition-all duration-200 bg-white relative z-10 " <>
        if(@is_current, do: "border-[#943a9e] border-2 ring-4 ring-purple-100", else: "border-[#2fa8b6] hover:border-[#1d747e] hover:shadow-md")}
    >
      
      <%= if @is_current do %>
        <div class="absolute -top-3 -right-2 text-[#943a9e] bg-white rounded-full">
          <i class="fa-solid fa-circle-check text-xl"></i>
        </div>
      <% end %>

      <div class="flex items-start justify-between">
        <div class="flex items-center gap-2.5">
          <%= if @node["node_type"] == "MATERIAL" do %>
            <div class="bg-orange-50 text-orange-600 rounded p-1.5 flex items-center justify-center w-8 h-8 flex-shrink-0">
              <%= case Map.get(@node, "material_type") || "git" do %>
                <% "git" -> %> <i class="fa-brands fa-git-alt text-lg"></i>
                <% "hg" -> %> <i class="fa-solid fa-code-fork text-lg"></i>
                <% "svn" -> %> <i class="fa-solid fa-database text-lg"></i>
                <% "p4" -> %> <i class="fa-solid fa-terminal text-lg"></i>
                <% "tfs" -> %> <i class="fa-brands fa-windows text-lg"></i>
                <% "package" -> %> <i class="fa-solid fa-box text-lg"></i>
                <% "plugin" -> %> <i class="fa-solid fa-plug text-lg"></i>
                <% _ -> %> <i class="fa-solid fa-circle-question text-lg"></i>
              <% end %>
            </div>
            <div class="flex flex-col min-w-0">
              <span class="text-[9px] text-orange-600 font-bold uppercase tracking-wider">Material</span>
              <span class="text-xs font-semibold text-gray-700 truncate w-40" title={@node["name"]}>
                {Path.basename(@node["name"] || "")}
              </span>
            </div>
          <% else %>
            <div class="bg-cyan-50 text-cyan-600 rounded p-1.5 flex items-center justify-center w-8 h-8 flex-shrink-0">
              <i class="fa-solid fa-network-wired text-lg"></i>
            </div>
            <div class="flex flex-col min-w-0">
              <span class="text-[9px] text-cyan-600 font-bold uppercase tracking-wider">Pipeline</span>
              <.link navigate={~p"/pipelines?search=#{@node["name"]}"} class="text-xs font-semibold text-[#2d6ca2] hover:underline truncate w-40" title={@node["name"]}>
                {@node["name"]}
              </.link>
            </div>
          <% end %>
        </div>
        
        <%= if @is_current do %>
          <span class="text-[9px] bg-purple-100 text-[#943a9e] font-extrabold px-1.5 py-0.5 rounded uppercase font-mono">Current</span>
        <% end %>
      </div>

      <div class="mt-3 border-t border-gray-100 pt-2.5">
        <%= if @node["node_type"] == "MATERIAL" do %>
          <%= for rev <- @node["material_revisions"] || [] do %>
            <%= for mod <- rev["modifications"] || [] do %>
              <div class="flex flex-col text-xs text-gray-500 gap-1">
                <div class="flex items-center justify-between">
                  <span class="font-bold text-gray-700 truncate w-32">{mod["user"]}</span>
                  <.link navigate={mod["locator"]} class="font-mono text-cyan-600 hover:underline">{String.slice(mod["revision"], 0, 8)}</.link>
                </div>
                <p class="text-gray-600 italic line-clamp-2 mt-0.5 font-medium">"{mod["comment"]}"</p>
                <span class="text-[9px] text-gray-400 font-medium mt-0.5">{mod["modified_time"]}</span>
              </div>
            <% end %>
          <% end %>
        <% else %>
          <%= for inst <- @node["instances"] || [] do %>
            <div class="flex flex-col gap-2">
              <div class="flex justify-between items-center text-xs">
                <span class="font-mono text-gray-600 font-bold">Instance: {inst["label"]}</span>
                <.link navigate={inst["locator"]} class="text-cyan-600 hover:underline font-bold">VSM</.link>
              </div>
              
              <ul class="flex flex-wrap gap-1 mt-1">
                <%= for stage <- inst["stages"] || [] do %>
                  <li class="relative">
                    <.link
                      navigate={stage["locator"]}
                      class={"w-5 h-5 block rounded-sm transition-transform hover:scale-105 " <> stage_status_bg(stage["status"])}
                      title={"#{stage["name"]} (#{stage["status"]})"}
                      aria-label={"#{stage["name"]} (#{stage["status"]})"}
                    >
                    </.link>
                  </li>
                <% end %>
              </ul>
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
    <div class="vsm-page px-8 py-8 bg-[#f4f8f9] min-h-screen">
      <div class="page-header flex justify-between items-center border-b border-gray-200 pb-4 mb-6">
        <div class="flex flex-col">
          <span class="text-[10px] uppercase tracking-wider text-gray-500 font-bold font-mono">Value Stream Map</span>
          <div class="flex items-baseline gap-4 mt-1">
            <div class="flex items-center gap-1.5 text-lg font-bold text-gray-700">
              <span class="text-[10px] text-gray-500 font-medium font-mono">{@entity_label}</span>
              <a href={@entity_locator} class="text-[#2d6ca2] hover:underline font-bold">{@entity_name}</a>
            </div>
            <div class="flex items-center gap-1.5 text-lg font-bold text-gray-700">
              <span class="text-[10px] text-gray-500 font-medium font-mono">{@entity_counter_label}</span>
              <h1 class="text-gray-900 font-extrabold font-mono">{@entity_counter}</h1>
            </div>
          </div>
        </div>
      </div>

      <div id="vsm-container" phx-hook="VSMGraph" class="vsm-container-wrapper relative border border-gray-200 rounded-lg p-10 bg-white shadow-sm overflow-x-auto min-h-[500px]">
        <svg id="vsm-svg" class="absolute top-0 left-0 pointer-events-none w-full h-full" style="z-index: 1;">
          <defs>
            <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M 0 1.5 L 8 5 L 0 8.5 z" fill="#2fa8b6" />
            </marker>
            <marker id="arrow-current" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M 0 1.5 L 8 5 L 0 8.5 z" fill="#943a9e" />
            </marker>
          </defs>
        </svg>

        <div class="flex justify-center items-stretch gap-16 min-w-[800px] relative z-10">
          <%= for level <- @vsm["levels"] do %>
            <div class="vsm-level flex flex-col justify-center gap-10 relative">
              <%= for node <- level["nodes"] do %>
                <.vsm_node_widget node={node} is_current={is_current?(node, @vsm)} />
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
