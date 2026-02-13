defmodule ExGoCDWeb.MaterialsLive do
  @moduledoc """
  Placeholder LiveView for the Materials page (SCM materials, pipeline dependencies).
  Nav link points here so the header does not 404.
  """
  use ExGoCDWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Materials")
     |> assign(:current_path, "/materials")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard-message text-center" role="region" aria-label="Materials">
      <h2>Materials</h2>
      <p>Materials (SCM, pipeline dependencies) will be implemented in a later phase.</p>
    </div>
    """
  end
end
