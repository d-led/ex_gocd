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
     |> assign(:show_usages_modal, false)
     |> assign(:show_modifications_modal, false)
     |> assign(:active_material, nil)
     |> assign(:mod_search_text, "")
     |> assign(:mod_page_index, 0)
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
      {:noreply,
       socket
       |> assign(:active_material, material)
       |> assign(:show_usages_modal, true)}
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
       |> assign(:active_material, material)
       |> assign(:mod_search_text, "")
       |> assign(:mod_page_index, 0)
       |> assign(:show_modifications_modal, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_usages_modal, false)
     |> assign(:show_modifications_modal, false)
     |> assign(:active_material, nil)}
  end

  @impl true
  def handle_event("search_modifications", %{"value" => search_text}, socket) do
    {:noreply,
     socket
     |> assign(:mod_search_text, search_text)
     |> assign(:mod_page_index, 0)}
  end

  @impl true
  def handle_event("mod_prev_page", _params, socket) do
    new_index = max(0, socket.assigns.mod_page_index - 1)
    {:noreply, assign(socket, :mod_page_index, new_index)}
  end

  @impl true
  def handle_event("mod_next_page", _params, socket) do
    new_index = socket.assigns.mod_page_index + 1
    {:noreply, assign(socket, :mod_page_index, new_index)}
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
    if mat.type in ["git", "hg", "svn", "p4", "tfs", "pluggable_scm", "dependency"] do
      {username, email, revision, comment, time} =
        cond do
          String.contains?(mat.url || "", "gocd/gocd") ->
            {"Dmitry Ledentsov", "dmlled@yahoo.com", "05172d07f4f4a0765243628b94f6840f8dc5411a",
             "upgrade actions and fix compilation warnings", ~U[2026-06-11 12:00:00Z]}

          String.contains?(mat.url || "", "gocd/docs") ->
            {"GoCD Team", "support@gocd.org", "98a7b6c5d4e3f2a10987654321abcdef01234567",
             "Update materials page documentation for rewrite", ~U[2026-06-11 11:30:00Z]}

          true ->
            {"gocd-admin", "admin@gocd.org", "f0e1d2c3b4a5968776655443322110abcdef0123",
             "Initial commit for repository integration", ~U[2026-06-11 10:15:00Z]}
        end

      %{
        username: username,
        email: email,
        revision: revision,
        comment: comment,
        modified_time: time
      }
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
          <span class="help-question" title="A material is a cause for a pipeline to run.">?</span>
        </h1>
        <div class="search-box-wrapper" role="search" aria-label="Material filters">
          <form phx-change="search" phx-submit="search" id="material-search-form" class="search-form-wrapper">
            <i class="fa-solid fa-magnifying-glass search-icon-inside"></i>
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
              <div class="collapse-header">
                <div class="collapse-header-clickable" phx-click="toggle_material" phx-value-fingerprint={mat.fingerprint}>
                  <div class="header-details">
                    <div class="material-icon-wrapper" data-test-id="material-icon">
                      <div class="scm-logo-box">
                        <%= case mat.type do %>
                          <% "git" -> %> <i class="fa-brands fa-git-alt git-icon"></i> <span>git</span>
                          <% "hg" -> %> <i class="fa-solid fa-code-fork hg-icon"></i> <span>hg</span>
                          <% "svn" -> %> <i class="fa-solid fa-database svn-icon"></i> <span>svn</span>
                          <% "p4" -> %> <i class="fa-solid fa-terminal p4-icon"></i> <span>p4</span>
                          <% "tfs" -> %> <i class="fa-brands fa-windows tfs-icon"></i> <span>tfs</span>
                          <% _ -> %> <i class="fa-solid fa-circle-question default-icon"></i> <span>{mat.type}</span>
                        <% end %>
                      </div>
                    </div>
                    <div class="headerTitle">
                      <h4 class="headerTitleText material-url" title={mat.url} data-test-id="material-type">
                        {mat.url}
                      </h4>
                      <span class="headerTitleUrl" data-test-id="material-display-name">
                        {mat.url} [ {mat.branch} ]
                      </span>
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
                </div>

                <div class="actions">
                  <div class="icon-group">
                    <button class="icon-btn" title="Trigger Update" phx-click="trigger_update" phx-value-fingerprint={mat.fingerprint} data-test-id="trigger-update">
                      <i class="fa-solid fa-arrows-rotate"></i>
                    </button>
                    <button class="icon-btn" title="Show Usages" phx-click="show_usages" phx-value-fingerprint={mat.fingerprint} data-test-id="show-usages">
                      <i class="fa-solid fa-chart-pie"></i>
                    </button>
                    <button class="icon-btn" title="Show Modifications" phx-click="show_modifications" phx-value-fingerprint={mat.fingerprint} data-test-id="show-modifications">
                      <i class="fa-solid fa-list"></i>
                    </button>
                  </div>
                </div>

                <div class="collapse-toggle" phx-click="toggle_material" phx-value-fingerprint={mat.fingerprint}>
                  <i class="fa-solid fa-chevron-right"></i>
                </div>
              </div>

              <div class={"collapse-body #{if not MapSet.member?(@expanded_materials, mat.fingerprint), do: "hide", else: ""}"}>
                <div class="details-section">
                  <h3>Latest Modification Details</h3>
                  <%= if mat.modification do %>
                    <div class="detail-row">
                      <span class="detail-key">Username</span>
                      <span class="detail-colon">:</span>
                      <span class="detail-value">{mat.modification.username} &lt;{mat.modification.email}&gt;</span>
                    </div>
                    <div class="detail-row">
                      <span class="detail-key">Email</span>
                      <span class="detail-colon">:</span>
                      <span class="detail-value">{mat.modification.email || "(Not specified)"}</span>
                    </div>
                    <div class="detail-row">
                      <span class="detail-key">Revision</span>
                      <span class="detail-colon">:</span>
                      <span class="detail-value"><code>{mat.modification.revision}</code></span>
                    </div>
                    <div class="detail-row">
                      <span class="detail-key">Comment</span>
                      <span class="detail-colon">:</span>
                      <span class="detail-value">{mat.modification.comment}</span>
                    </div>
                    <div class="detail-row">
                      <span class="detail-key">Modified Time</span>
                      <span class="detail-colon">:</span>
                      <span class="detail-value">{Calendar.strftime(mat.modification.modified_time, "%d %b, %Y at %H:%M:%S Local Time")}</span>
                    </div>
                  <% else %>
                    <div class="detail-row empty">This material was never parsed</div>
                  <% end %>
                </div>

                <div class="details-section">
                  <h3>Material Attributes</h3>
                  <div class="detail-row">
                    <span class="detail-key">URL</span>
                    <span class="detail-colon">:</span>
                    <span class="detail-value">{mat.url}</span>
                  </div>
                  <%= if mat.branch do %>
                    <div class="detail-row">
                      <span class="detail-key">Branch</span>
                      <span class="detail-colon">:</span>
                      <span class="detail-value"><code>{mat.branch}</code></span>
                    </div>
                  <% end %>
                  <%= if mat.destination do %>
                    <div class="detail-row">
                      <span class="detail-key">Destination</span>
                      <span class="detail-colon">:</span>
                      <span class="detail-value"><code>{mat.destination}</code></span>
                    </div>
                  <% end %>
                  <div class="detail-row">
                    <span class="detail-key">Auto Update</span>
                    <span class="detail-colon">:</span>
                    <span class="detail-value">
                      <span class={"material-status_indicator " <> if not mat.auto_update, do: "auto-update-disabled", else: ""}></span>
                      <%= if mat.auto_update do %>
                        Active (polling)
                      <% else %>
                        Auto-update disabled
                      <% end %>
                    </span>
                  </div>
                </div>
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

      <!-- Usages Modal -->
      <%= if @show_usages_modal and @active_material do %>
        <div class="modal-backdrop" phx-click="close_modal" id="usages-modal-backdrop">
          <div class="gocd-modal" onclick="event.stopPropagation();" id="usages-modal">
            <div class="modal-header">
              <h3>Usages</h3>
              <button class="close-btn" phx-click="close_modal" aria-label="Close modal">&times;</button>
            </div>
            <div class="modal-body">
              <table class="modal-table">
                <thead>
                  <tr>
                    <th>PIPELINE</th>
                    <th>MATERIAL SETTING</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for p <- @active_material.pipelines do %>
                    <tr>
                      <td>
                        <.link navigate={~p"/pipelines?search=#{p}"} class="pipeline-link">
                          {p}
                        </.link>
                      </td>
                      <td>
                        <span class="edit-link">View/Edit Material</span>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
            <div class="modal-footer">
              <button class="ok-btn" phx-click="close_modal" id="usages-modal-ok">OK</button>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Modifications Modal -->
      <%= if @show_modifications_modal and @active_material do %>
        <%
          all_mods = get_all_modifications(@active_material)
          query = String.downcase(@mod_search_text)
          filtered_mods =
            if query == "" do
              all_mods
            else
              Enum.filter(all_mods, fn m ->
                String.contains?(String.downcase(m.revision || ""), query) or
                  String.contains?(String.downcase(m.comment || ""), query) or
                  String.contains?(String.downcase(m.username || ""), query)
              end)
            end
          page_size = 5
          total_pages = max(1, Float.ceil(length(filtered_mods) / page_size) |> trunc())
          current_page = min(@mod_page_index, total_pages - 1) |> max(0)
          paged_mods = Enum.slice(filtered_mods, (current_page * page_size), page_size)
        %>
        <div class="modal-backdrop" phx-click="close_modal" id="modifications-modal-backdrop">
          <div class="gocd-modal large" onclick="event.stopPropagation();" id="modifications-modal">
            <div class="modal-header">
              <h3>Modifications</h3>
              <button class="close-btn" phx-click="close_modal" aria-label="Close modal">&times;</button>
            </div>
            <div class="modal-sub-header">
              <div class="sub-header-title">
                <span class="scm-type">{String.capitalize(@active_material.type)} :</span>
                <span class="scm-url">{@active_material.url}</span>
              </div>
              <div class="modal-search">
                <form phx-change="search_modifications" phx-submit="search_modifications" id="mod-search-form" class="search-form-wrapper">
                  <i class="fa-solid fa-magnifying-glass search-icon-inside"></i>
                  <input
                    type="search"
                    name="value"
                    placeholder="Search in revision, comment or username"
                    value={@mod_search_text}
                    autocomplete="off"
                    aria-label="Search modifications"
                  />
                </form>
              </div>
            </div>
            <div class="modal-body">
              <div class="modifications-list">
                <%= if Enum.empty?(paged_mods) do %>
                  <div class="no-mods">No matching modifications found</div>
                <% else %>
                  <%= for mod <- paged_mods do %>
                    <div class="mod-row">
                      <div class="mod-left">
                        <span class="mod-user">{mod.username}</span>
                        <span class="mod-time">{Calendar.strftime(mod.modified_time, "%d %b, %Y at %H:%M:%S")} Local Time</span>
                      </div>
                      <div class="mod-middle">
                        <span class="mod-comment">{mod.comment}</span>
                      </div>
                      <div class="mod-right">
                        <span class="mod-rev">{String.slice(mod.revision, 0, 10)}...</span>
                        <span class="mod-divider">|</span>
                        <.link navigate={~p"/materials/value_stream_map/#{@active_material.fingerprint}/#{mod.revision}"} class="mod-vsm">VSM</.link>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
              <div class="modal-pagination">
                <button class="page-btn" phx-click="mod_prev_page" disabled={current_page <= 0} id="mod-prev-btn">Previous</button>
                <button class="page-btn" phx-click="mod_next_page" disabled={(current_page + 1) * page_size >= length(filtered_mods)} id="mod-next-btn">Next</button>
              </div>
            </div>
            <div class="modal-footer">
              <button class="ok-btn" phx-click="close_modal" id="modifications-modal-ok">OK</button>
            </div>
          </div>
        </div>
      <% end %>

      <footer class="gocd-footer">
        <div class="footer-left">
          Copyright &copy; Thoughtworks, Inc. Licensed under <a href="https://www.apache.org/licenses/LICENSE-2.0" target="_blank" rel="noopener noreferrer">Apache License, Version 2.0</a>. GoCD includes <a href="#">third-party software</a>.
          <br/>
          GoCD Version: 25.4.0 (21793-c8358258163d7b9833ab3b1b18a2f459999936b03a).
        </div>
        <div class="footer-right">
          <a href="#" title="GitHub"><i class="fa-brands fa-github"></i></a>
          <a href="#" title="Chat"><i class="fa-solid fa-comments"></i></a>
          <a href="#" title="Documentation"><i class="fa-solid fa-book"></i></a>
          <a href="#" title="Plugins"><i class="fa-solid fa-plug"></i></a>
          <a href="#" title="API"><i class="fa-solid fa-code"></i></a>
          <a href="#" title="Feed"><i class="fa-solid fa-rss"></i></a>
        </div>
      </footer>
    </div>
    """
  end

  defp get_all_modifications(material) do
    cond do
      String.contains?(material.url || "", "gocd/gocd") ->
        [
          %{
            username: "Dmitry Ledentsov <dmlled@yahoo.com>",
            revision: "05172d07f4f4a0765243628b94f6840f8dc5411a",
            comment: "upgrade actions and fix compilation warnings",
            modified_time: ~U[2026-06-11 12:00:00Z]
          },
          %{
            username: "Dmitry Ledentsov <dmlled@yahoo.com>",
            revision: "07ad87411d8c2e3612847d08f4f4a9846c9811ae",
            comment: "Update dependencies and improve Gradle wrapper scripts",
            modified_time: ~U[2026-06-11 11:30:00Z]
          },
          %{
            username: "Dmitry Ledentsov <dmlled@yahoo.com>",
            revision: "3318426632c028ba986e30cb7810df67cf9dbe80",
            comment: "change the action name to use dynamic variables",
            modified_time: ~U[2026-04-24 23:34:39Z]
          }
        ]

      String.contains?(material.url || "", "gocd/docs") ->
        [
          %{
            username: "GoCD Team <support@gocd.org>",
            revision: "98a7b6c5d4e3f2a10987654321abcdef01234567",
            comment: "Update materials page documentation for rewrite",
            modified_time: ~U[2026-06-11 11:30:00Z]
          },
          %{
            username: "GoCD Team <support@gocd.org>",
            revision: "87a6b5c4d3e2f1a0987654321abcdef012345678",
            comment: "Clarify pipeline dependencies layout in documentation",
            modified_time: ~U[2026-06-11 10:00:00Z]
          }
        ]

      true ->
        [
          %{
            username: "gocd-admin <admin@gocd.org>",
            revision: "f0e1d2c3b4a5968776655443322110abcdef0123",
            comment: "Initial commit for repository integration",
            modified_time: ~U[2026-06-11 10:15:00Z]
          }
        ]
    end
  end
end
