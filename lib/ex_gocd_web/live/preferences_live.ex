defmodule ExGoCDWeb.PreferencesLive do
  @moduledoc """
  User Preferences page — auto-refresh, pipelines per page, and display settings.

  Covers ruby spec: PreferencesPage.spec
  """
  use ExGoCDWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Preferences")
     |> assign(:auto_refresh, true)
     |> assign(:pipelines_per_page, 25)
     |> assign(:flash_info, nil)}
  end

  @impl true
  def handle_event("toggle_auto_refresh", _params, socket) do
    new_val = !socket.assigns.auto_refresh

    {:noreply,
     socket
     |> assign(:auto_refresh, new_val)
     |> put_flash(:info, "Auto-refresh #{if new_val, do: "enabled", else: "disabled"}.")}
  end

  @impl true
  def handle_event("set_pipelines_per_page", %{"value" => value}, socket) do
    case Integer.parse(value) do
      {n, _} when n >= 5 and n <= 100 ->
        {:noreply,
         socket
         |> assign(:pipelines_per_page, n)
         |> put_flash(:info, "Pipelines per page set to #{n}.")}

      _ ->
        {:noreply, socket |> put_flash(:error, "Must be a number between 5 and 100.")}
    end
  end

  @impl true
  def handle_event("clear_flash", _params, socket) do
    {:noreply, socket |> assign(:flash_info, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="preferences-page min-h-screen bg-[#f4f8f9] text-[#333] font-sans pb-12">
      <div class="max-w-3xl mx-auto px-6 py-8">
        <div class="bg-white rounded border border-[#d6e0e2] shadow-sm overflow-hidden">
          <!-- Header -->
          <div class="bg-[#e7eef0] px-6 py-4 border-b border-[#d6e0e2]">
            <h1 class="text-lg font-bold text-slate-800">
              <i class="fa fa-sliders mr-2 text-[#943a9e]"></i>Preferences
            </h1>
            <p class="text-xs text-slate-500 mt-1">Customize your GoCD experience</p>
          </div>
          
    <!-- Flash -->
          <%= if @flash_info do %>
            <div class="mx-6 mt-4 bg-[#dbf1d9] border border-[#a3d7a8] text-[#298a4c] px-4 py-3 rounded flex justify-between items-center text-sm">
              <span class="font-medium">{@flash_info}</span>
              <button phx-click="clear_flash" class="text-[#298a4c] hover:text-emerald-900">
                <i class="fa fa-times"></i>
              </button>
            </div>
          <% end %>
          
    <!-- Settings -->
          <div class="divide-y divide-[#e9edef]">
            <!-- Auto-refresh -->
            <div class="px-6 py-5 flex items-center justify-between">
              <div>
                <p class="text-sm font-bold text-slate-700">Auto-refresh Dashboard</p>
                <p class="text-xs text-slate-400 mt-0.5">
                  Automatically refresh the pipeline dashboard every few seconds.
                </p>
              </div>
              <button
                phx-click="toggle_auto_refresh"
                class={[
                  "relative inline-flex h-6 w-11 items-center rounded-full transition-colors",
                  if(@auto_refresh, do: "bg-[#943a9e]", else: "bg-slate-300")
                ]}
              >
                <span class={[
                  "inline-block h-4 w-4 transform rounded-full bg-white transition-transform",
                  if(@auto_refresh, do: "translate-x-6", else: "translate-x-1")
                ]}>
                </span>
              </button>
            </div>
            
    <!-- Pipelines per page -->
            <div class="px-6 py-5">
              <p class="text-sm font-bold text-slate-700 mb-3">Pipelines per page</p>
              <p class="text-xs text-slate-400 mb-4">
                Number of pipeline groups shown per page on the dashboard (5–100).
              </p>
              <form phx-submit="set_pipelines_per_page" class="flex items-center gap-3">
                <input
                  type="number"
                  name="value"
                  value={@pipelines_per_page}
                  min="5"
                  max="100"
                  class="w-24 px-3 py-1.5 rounded border border-[#d6e0e2] text-xs text-slate-700 focus:outline-none focus:border-[#943a9e]"
                />
                <button
                  type="submit"
                  class="px-3 py-1.5 rounded bg-[#943a9e] hover:bg-purple-700 text-white text-xs font-semibold border border-purple-700 transition-all"
                >
                  Save
                </button>
              </form>
            </div>
            
    <!-- Display Info -->
            <div class="px-6 py-5">
              <h3 class="text-sm font-bold text-slate-700 mb-2">Current Settings</h3>
              <div class="text-xs text-slate-500 space-y-1">
                <p>
                  Auto-refresh:
                  <span class="font-semibold text-slate-700">
                    {if @auto_refresh, do: "On", else: "Off"}
                  </span>
                </p>
                <p>
                  Pipelines per page:
                  <span class="font-semibold text-slate-700">{@pipelines_per_page}</span>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
