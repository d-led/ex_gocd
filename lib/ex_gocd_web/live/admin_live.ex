defmodule ExGoCDWeb.AdminLive do
  @moduledoc """
  Placeholder LiveView for the Admin section (pipelines config, server config, etc.).
  Nav link points here so the header does not 404.
  """
  use ExGoCDWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:current_path, "/admin")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard-message text-center" role="region" aria-label="Admin">
      <h2>Admin</h2>
      <p>Admin (pipelines, environments, server configuration) will be implemented in a later phase.</p>
    </div>
    """
  end
end
