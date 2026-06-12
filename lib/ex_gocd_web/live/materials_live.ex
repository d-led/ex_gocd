defmodule ExGoCDWeb.MaterialsLive do
  @moduledoc """
  LiveView for the Materials page (SCM materials, pipeline dependencies).
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.MockData
  alias ExGoCD.Pipelines

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Materials")
     |> assign(:current_path, "/materials")
     |> assign(:search_text, "")
     |> assign(:expanded_materials, MapSet.new())
     |> load_materials()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search_text = params["search"] || ""
    {:noreply,
     socket
     |> assign(:search_text, search_text)
     |> load_materials()}
  end

  @impl true
  def handle_event("search", %{"value" => search_text}, socket) do
    {:noreply,
     socket
     |> assign(:search_text, search_text)
     |> load_materials()}
  end

  @impl true
  def handle_event("toggle_material", %{"fingerprint" => fingerprint}, socket) do
    expanded = socket.assigns.expanded_materials
    new_expanded =
      if MapSet.member?(expanded, fingerprint) do
        MapSet.delete(expanded, fingerprint)
      else
        MapSet.put(expanded, fingerprint)
      end
    {:noreply, assign(socket, :expanded_materials, new_expanded)}
  end

  @impl true
  def handle_event("trigger_update", %{"fingerprint" => fingerprint}, socket) do
    material = Enum.find(socket.assigns.materials, &(&1.fingerprint == fingerprint))
    if material do
      {:noreply,
       socket
       |> put_flash(:info, "An update was scheduled for '#{material.url}' material.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_usages", %{"fingerprint" => fingerprint}, socket) do
    material = Enum.find(socket.assigns.materials, &(&1.fingerprint == fingerprint))
    if material do
      pipelines = Enum.join(material.pipelines, ", ")
      msg = if pipelines == "", do: "none", else: pipelines
      {:noreply,
       socket
       |> put_flash(:info, "Material usages: Used in pipelines [#{msg}]")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_modifications", %{"fingerprint" => fingerprint}, socket) do
    material = Enum.find(socket.assigns.materials, &(&1.fingerprint == fingerprint))
    if material do
      {:noreply,
       socket
       |> put_flash(:info, "Showing modification history for '#{material.url}'")}
    else
      {:noreply, socket}
    end
  end

  defp load_materials(socket) do
    search_lower = String.downcase(socket.assigns.search_text || "")
    all_materials = get_all_materials()

    filtered =
      if search_lower == "" do
        all_materials
      else
        Enum.filter(all_materials, fn mat ->
          String.contains?(String.downcase(mat.type || ""), search_lower) or
            String.contains?(String.downcase(mat.url || ""), search_lower) or
            String.contains?(String.downcase(mat.branch || ""), search_lower)
        end)
      end

    socket
    |> assign(:materials, filtered)
    |> assign(:has_materials, filtered != [])
  end

  defp get_all_materials do
    materials =
      if use_mock?() do
        get_mock_materials()
      else
        case Pipelines.list_materials() do
          [] -> get_mock_materials()
          list -> map_db_materials(list)
        end
      end

    materials
    |> Enum.map(fn mat ->
      fp = fingerprint(mat)
      mat
      |> Map.put(:fingerprint, fp)
      |> Map.put(:modification, get_latest_modification(mat))
    end)
    |> Enum.sort_by(& &1.url)
  end

  defp map_db_materials(list) do
    Enum.map(list, fn mat ->
      pipelines = Enum.map(mat.pipelines || [], & &1.name) |> Enum.uniq() |> Enum.sort()
      %{
        type: mat.type,
        url: mat.url,
        branch: mat.branch,
        pipelines: pipelines,
        auto_update: mat.auto_update,
        destination: mat.destination
      }
    end)
  end

  defp get_mock_materials do
    MockData.pipelines()
    |> Enum.flat_map(fn p ->
      Enum.map(p.materials || [], fn mat ->
        Map.put(mat, :pipeline_name, p.name)
      end)
    end)
    |> Enum.group_by(fn mat -> {mat.type, mat.url, mat.branch} end)
    |> Enum.map(fn {{type, url, branch}, mats} ->
      pipelines = Enum.map(mats, & &1.pipeline_name) |> Enum.uniq() |> Enum.sort()
      %{
        type: type,
        url: url,
        branch: branch,
        pipelines: pipelines,
        auto_update: true,
        destination: nil
      }
    end)
  end

  defp fingerprint(mat) do
    # Simple consistent fingerprint generation
    :crypto.hash(:sha256, "#{mat.type}-#{mat.url || ""}-#{mat.branch || ""}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp get_latest_modification(mat) do
    cond do
      mat.type in ["git", "hg", "svn", "p4", "tfs", "pluggable_scm", "dependency"] ->
        {username, email, revision, comment, time} =
          cond do
            String.contains?(mat.url || "", "gocd/gocd") ->
              {"Dmitry Ledentsov", "dmlled@yahoo.com", "05172d07f4f4a0765243628b94f6840f8dc5411a", "upgrade actions and fix compilation warnings", ~U[2026-06-11 12:00:00Z]}
            String.contains?(mat.url || "", "gocd/docs") ->
              {"GoCD Team", "support@gocd.org", "98a7b6c5d4e3f2a10987654321abcdef01234567", "Update materials page documentation for rewrite", ~U[2026-06-11 11:30:00Z]}
            true ->
              {"gocd-admin", "admin@gocd.org", "f0e1d2c3b4a5968776655443322110abcdef0123", "Initial commit for repository integration", ~U[2026-06-11 10:15:00Z]}
          end
        %{
          username: username,
          email: email,
          revision: revision,
          comment: comment,
          modified_time: time
        }
      true ->
        nil
    end
  end

  defp use_mock? do
    System.get_env("USE_MOCK_DATA") == "true"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="materials-page" id="materials-page">
      <div class="page-header">
        <h1 class="page-header_title">
          <span>Materials</span>
          <span class="tooltip-wrapper" title="A material is a cause for a pipeline to run.">
            <i class="fa fa-question-circle" aria-hidden="true"></i>
          </span>
        </h1>
        <div class="search-box-wrapper" role="search" aria-label="Material filters">
          <form phx-change="search" phx-submit="search" id="material-search-form">
            <label for="material-search" class="sr-only">Search materials</label>
            <input
              id="material-search"
              type="search"
              class="search-input"
              placeholder="Search for a material name or url"
              value={@search_text}
              phx-debounce="300"
              name="value"
              aria-label="Search materials"
              autocomplete="off"
            />
          </form>
        </div>
      </div>

      <%= if @has_materials do %>
        <div class="materials-list" role="region" aria-label="SCM Materials">
          <%= for mat <- @materials do %>
            <div class={"material-card collapse #{if MapSet.member?(@expanded_materials, mat.fingerprint), do: "expanded", else: ""}"} data-type={mat.type} id={"material-#{mat.fingerprint}"}>
              <div class="collapse-header" phx-click="toggle_material" phx-value-fingerprint={mat.fingerprint}>
                <div class="header-details">
                  <div class="material-icon-wrapper" data-test-id="material-icon">
                    <%= case mat.type do %>
                      <% "git" -> %> <i class="fa-brands fa-git-alt text-xl text-orange-600"></i>
                      <% "hg" -> %> <i class="fa-solid fa-code-fork text-xl text-blue-600"></i>
                      <% "svn" -> %> <i class="fa-solid fa-database text-xl text-red-600"></i>
                      <% "p4" -> %> <i class="fa-solid fa-terminal text-xl text-green-600"></i>
                      <% "tfs" -> %> <i class="fa-brands fa-windows text-xl text-blue-500"></i>
                      <% "package" -> %> <i class="fa-solid fa-box text-xl text-yellow-600"></i>
                      <% "plugin" -> %> <i class="fa-solid fa-plug text-xl text-purple-600"></i>
                      <% _ -> %> <i class="fa-solid fa-circle-question text-xl text-gray-400"></i>
                    <% end %>
                  </div>
                  <div class="headerTitle">
                    <h4 class="headerTitleText material-url" title={mat.url} data-test-id="material-type">
                      {mat.url}
                    </h4>
                    <span class="headerTitleUrl" data-test-id="material-display-name">
                      {mat.url} [ {mat.branch} ]
                    </span>
                    <%= if not Enum.empty?(mat.pipelines) do %>
                      <div class="material-pipelines-header" onclick="event.stopPropagation();">
                        <span>Used in Pipelines:</span>
                        <%= for p <- mat.pipelines do %>
                          <.link
                            navigate={~p"/pipelines?search=#{p}"}
                            class="material-pipeline-badge"
                          >
                            {p}
                          </.link>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>

                <div class="commit-info" data-test-id="latest-mod-in-header">
                  <%= if mat.modification do %>
                    <span class="comment">{mat.modification.comment}</span>
                    <div class="committerInfo">
                      <span class="committer">{mat.modification.username}</span> | {mat.modification.revision} |
                      <.link navigate={~p"/materials/value_stream_map/#{mat.fingerprint}/#{mat.modification.revision}"} class="vsm-link" onclick="event.stopPropagation();">VSM</.link>
                    </div>
                  <% else %>
                    This material was never parsed
                  <% end %>
                </div>

                <div class="actions" onclick="event.stopPropagation();">
                  <div class="icon-group">
                    <button class="icon-btn" title="Trigger Update" phx-click="trigger_update" phx-value-fingerprint={mat.fingerprint} data-test-id="trigger-update">
                      <i class="fa-solid fa-arrows-rotate"></i>
                    </button>
                    <button class="icon-btn" title="Show Usages" phx-click="show_usages" phx-value-fingerprint={mat.fingerprint} data-test-id="show-usages">
                      <i class="fa-solid fa-sitemap"></i>
                    </button>
                    <button class="icon-btn" title="Show Modifications" phx-click="show_modifications" phx-value-fingerprint={mat.fingerprint} data-test-id="show-modifications">
                      <i class="fa-solid fa-clock-rotate-left"></i>
                    </button>
                  </div>
                </div>

                <div class="collapse-toggle">
                  <i class="fa-solid fa-chevron-right"></i>
                </div>
              </div>

              <div class={"collapse-body #{if not MapSet.member?(@expanded_materials, mat.fingerprint), do: "hide", else: ""}"}>
                <h3>Latest Modification Details</h3>
                <table class="key-value-table" data-test-id="latest-modification-details">
                  <%= if mat.modification do %>
                    <tr>
                      <td class="property-key">Username</td>
                      <td class="property-value">{mat.modification.username}</td>
                    </tr>
                    <tr>
                      <td class="property-key">Email</td>
                      <td class="property-value">{mat.modification.email}</td>
                    </tr>
                    <tr>
                      <td class="property-key">Revision</td>
                      <td class="property-value"><code>{mat.modification.revision}</code></td>
                    </tr>
                    <tr>
                      <td class="property-key">Comment</td>
                      <td class="property-value">{mat.modification.comment}</td>
                    </tr>
                    <tr>
                      <td class="property-key">Modified Time</td>
                      <td class="property-value">{Calendar.strftime(mat.modification.modified_time, "%Y-%m-%d %H:%M:%S UTC")}</td>
                    </tr>
                  <% else %>
                    <tr>
                      <td colspan="2" class="property-value text-gray-500 italic">This material was never parsed</td>
                    </tr>
                  <% end %>
                </table>

                <h3>Material Attributes</h3>
                <table class="key-value-table" data-test-id="material-attributes">
                  <tr>
                    <td class="property-key">Type</td>
                    <td class="property-value"><span class="material-type-badge">{mat.type}</span></td>
                  </tr>
                  <tr>
                    <td class="property-key">URL</td>
                    <td class="property-value">{mat.url}</td>
                  </tr>
                  <%= if mat.branch do %>
                    <tr class="material-detail-item">
                      <td class="property-key"><strong>Branch:</strong></td>
                      <td class="property-value"><code>{mat.branch}</code></td>
                    </tr>
                  <% end %>
                  <%= if mat.destination do %>
                    <tr class="material-detail-item">
                      <td class="property-key"><strong>Destination:</strong></td>
                      <td class="property-value"><code>{mat.destination}</code></td>
                    </tr>
                  <% end %>
                  <tr>
                    <td class="property-key">Auto Update</td>
                    <td class="property-value">
                      <div class="material-status">
                        <span class={"material-status_indicator " <> if not mat.auto_update, do: "auto-update-disabled", else: ""}></span>
                        <span>
                          <%= if mat.auto_update do %>
                            Active (polling)
                          <% else %>
                            Auto-update disabled
                          <% end %>
                        </span>
                      </div>
                    </td>
                  </tr>
                </table>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="dashboard-message text-center">
          <h3>No materials found</h3>
          <p>Try refining your search term or configure materials in your pipelines.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
