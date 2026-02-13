defmodule ExGoCDWeb.AgentsLive do
  @moduledoc """
  LiveView for displaying and managing agents.
  Real-time updates via Phoenix channel (agents:updates); hook pushes refresh_agents.
  Admin-only actions (enable/disable/delete, bulk actions, job history link) are
  gated by is_user_admin (from AgentPolicy).
  """
  use ExGoCDWeb, :live_view
  alias ExGoCD.Agents
  alias ExGoCD.Scheduler

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe so any agent registration/update is broadcast to this LiveView
    Agents.subscribe()

    {:ok,
     socket
     |> assign(
       agents: fetch_agents(),
       selected_agents: MapSet.new(),
       agent_type: :static,
       filter: "",
       sort_column: "hostname",
       sort_order: :asc,
       page_title: "Agents",
       current_path: "/agents",
       pending_scheduled: pending_scheduled_count()
     )}
  end

  @impl true
  def handle_info({event, _agent}, socket)
      when event in [:agent_registered, :agent_updated, :agent_enabled, :agent_disabled, :agent_deleted] do
    new_agents = fetch_agents()
    selected =
      if socket.assigns[:selected_agents] do
        MapSet.intersection(socket.assigns.selected_agents, MapSet.new(Enum.map(new_agents, & &1.uuid)))
      else
        MapSet.new()
      end
    {:noreply, assign(socket, agents: new_agents, selected_agents: selected)}
  end

  @impl true
  def handle_event("refresh_agents", _params, socket) do
    new_agents = fetch_agents()
    selected =
      if socket.assigns[:selected_agents] do
        MapSet.intersection(socket.assigns.selected_agents, MapSet.new(Enum.map(new_agents, & &1.uuid)))
      else
        MapSet.new()
      end
    {:noreply, assign(socket, agents: new_agents, selected_agents: selected)}
  end

  @impl true
  def handle_event("toggle_select", %{"uuid" => uuid}, socket) do
    if socket.assigns[:is_user_admin] do
      selected =
        if MapSet.member?(socket.assigns.selected_agents, uuid) do
          MapSet.delete(socket.assigns.selected_agents, uuid)
        else
          MapSet.put(socket.assigns.selected_agents, uuid)
        end

      {:noreply, assign(socket, selected_agents: selected)}
    else
      return_forbidden(socket)
    end
  end

  def handle_event("toggle_select_all", _params, socket) do
    if socket.assigns[:is_user_admin] do
      agent_uuids = Enum.map(socket.assigns.agents, & &1.uuid) |> MapSet.new()

      selected =
        if MapSet.size(socket.assigns.selected_agents) == length(socket.assigns.agents) do
          MapSet.new()
        else
          agent_uuids
        end

      {:noreply, assign(socket, selected_agents: selected)}
    else
      return_forbidden(socket)
    end
  end

  def handle_event("switch_tab", %{"type" => "static"}, socket) do
    {:noreply, assign(socket, agent_type: :static, selected_agents: MapSet.new())}
  end

  def handle_event("switch_tab", %{"type" => "elastic"}, socket) do
    {:noreply, assign(socket, agent_type: :elastic, selected_agents: MapSet.new())}
  end

  def handle_event("filter", %{"value" => value}, socket) do
    {:noreply, assign(socket, filter: String.trim(value))}
  end

  def handle_event("sort", %{"column" => column}, socket) do
    {sort_column, sort_order} =
      if socket.assigns.sort_column == column do
        order = if socket.assigns.sort_order == :asc, do: :desc, else: :asc
        {column, order}
      else
        {column, :asc}
      end

    {:noreply, assign(socket, sort_column: sort_column, sort_order: sort_order)}
  end

  def handle_event("bulk_delete", _params, socket) do
    if socket.assigns[:is_user_admin] do
      Enum.each(socket.assigns.selected_agents, fn uuid ->
        Agents.delete_agent(uuid)
      end)

      {:noreply,
       socket
       |> put_flash(:info, "Selected agents deleted")
       |> assign(selected_agents: MapSet.new())}
    else
      return_forbidden(socket)
    end
  end

  def handle_event("bulk_enable", _params, socket) do
    if socket.assigns[:is_user_admin] do
      Enum.each(socket.assigns.selected_agents, fn uuid ->
        Agents.enable_agent(uuid)
      end)

      {:noreply,
       socket
       |> put_flash(:info, "Selected agents enabled")
       |> assign(selected_agents: MapSet.new())}
    else
      return_forbidden(socket)
    end
  end

  def handle_event("bulk_disable", _params, socket) do
    if socket.assigns[:is_user_admin] do
      Enum.each(socket.assigns.selected_agents, fn uuid ->
        Agents.disable_agent(uuid)
      end)

      {:noreply,
       socket
       |> put_flash(:info, "Selected agents disabled")
       |> assign(selected_agents: MapSet.new())}
    else
      return_forbidden(socket)
    end
  end

  def handle_event("enable", %{"uuid" => uuid}, socket) do
    if socket.assigns[:is_user_admin] do
      case Agents.enable_agent(uuid) do
        {:ok, _agent} ->
          {:noreply, put_flash(socket, :info, "Agent enabled")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to enable agent")}
      end
    else
      return_forbidden(socket)
    end
  end

  def handle_event("disable", %{"uuid" => uuid}, socket) do
    if socket.assigns[:is_user_admin] do
      case Agents.disable_agent(uuid) do
        {:ok, _agent} ->
          {:noreply, put_flash(socket, :info, "Agent disabled")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to disable agent")}
      end
    else
      return_forbidden(socket)
    end
  end

  def handle_event("schedule_test_job", _params, socket) do
    if socket.assigns[:is_user_admin] do
      case Scheduler.schedule_job(%{}) do
        {:ok, _id} ->
          {:noreply,
           socket
           |> put_flash(:info, "Job scheduled. Next idle agent will pick it up.")
           |> assign(pending_scheduled: pending_scheduled_count())}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to schedule job")}
      end
    else
      return_forbidden(socket)
    end
  end

  def handle_event("delete", %{"uuid" => uuid}, socket) do
    if socket.assigns[:is_user_admin] do
      case Agents.delete_agent(uuid) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "Agent deleted")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete agent")}
      end
    else
      return_forbidden(socket)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="agents-page" id="agents-page" phx-hook="AgentsUpdates">
      <div class="page-header">
        <h1 class="page-header_title">
          <span>Agents</span>
          <span class="tooltip-wrapper">
            <i class="fa fa-question-circle" aria-hidden="true"></i>
          </span>
        </h1>
      </div>

    <!-- Tabs -->
      <div class="agents-tabs">
        <button
          type="button"
          class={"tab-button " <> if @agent_type == :static, do: "active", else: ""}
          phx-click="switch_tab"
          phx-value-type="static"
        >
          STATIC
        </button>
        <button
          type="button"
          class={"tab-button " <> if @agent_type == :elastic, do: "active", else: ""}
          phx-click="switch_tab"
          phx-value-type="elastic"
        >
          ELASTIC
        </button>
      </div>

    <!-- Bulk Actions & Stats -->
      <div class="agents-controls">
        <%= if @is_user_admin do %>
          <div class="bulk-actions">
            <button
              type="button"
              class="btn-small btn-danger"
              phx-click="bulk_delete"
              disabled={MapSet.size(@selected_agents) == 0}
              data-confirm="Are you sure you want to delete the selected agents?"
            >
              DELETE
            </button>
            <button
              type="button"
              class="btn-small"
              phx-click="bulk_enable"
              disabled={MapSet.size(@selected_agents) == 0}
            >
              ENABLE
            </button>
            <button
              type="button"
              class="btn-small"
              phx-click="bulk_disable"
              disabled={MapSet.size(@selected_agents) == 0}
            >
              DISABLE
            </button>
            <button type="button" class="btn-small" disabled={MapSet.size(@selected_agents) == 0}>
              ENVIRONMENTS
            </button>
            <button type="button" class="btn-small" disabled={MapSet.size(@selected_agents) == 0}>
              RESOURCES
            </button>
            <button
              type="button"
              class="btn-small btn-primary"
              phx-click="schedule_test_job"
              title="Add a test job to the queue; next idle agent will run it (GoCD-style scheduling)"
            >
              SCHEDULE TEST JOB
            </button>
          </div>
        <% end %>

        <div class="agents-stats">
          <span>Total</span>
          <span class="stats-separator">:</span>
          <span class="stats-value">{total_count(@agents, @agent_type)}</span>

          <span class="stats-label">Pending</span>
          <span class="stats-separator">:</span>
          <span class="stats-value">{pending_count(@agents, @agent_type)}</span>

          <span class="stats-label">Enabled</span>
          <span class="stats-separator">:</span>
          <span class="stats-value stats-enabled">{enabled_count(@agents, @agent_type)}</span>

          <span class="stats-label">Disabled</span>
          <span class="stats-separator">:</span>
          <span class="stats-value stats-disabled">
            {disabled_count(@agents, @agent_type)}
          </span>

          <span class="stats-label">Queued jobs</span>
          <span class="stats-separator">:</span>
          <span class="stats-value">{@pending_scheduled}</span>
        </div>

        <div class="search-box">
          <i class="fa fa-search" aria-hidden="true"></i>
          <input
            type="text"
            name="filter"
            placeholder="Filter Agents"
            value={@filter}
            phx-change="filter"
            phx-debounce="200"
            aria-label="Filter agents by name, IP, resources, or environments"
          />
        </div>
      </div>

    <!-- Agents Table -->
      <div class="agents-table-container">
        <table class="agents-table">
          <thead>
            <tr>
              <%= if @is_user_admin do %>
                <th class="checkbox-cell">
                  <input
                    type="checkbox"
                    checked={
                      (agents = displayed_agents(@agents, @agent_type, @filter, @sort_column, @sort_order)) != [] &&
                        MapSet.size(@selected_agents) == length(agents)
                    }
                    phx-click="toggle_select_all"
                  />
                </th>
              <% end %>
              <th class="sortable" phx-click="sort" phx-value-column="hostname" role="button" tabindex="0">
                AGENT NAME <i class={sort_icon_class("hostname", @sort_column, @sort_order)} aria-hidden="true"></i>
              </th>
              <th class="sortable" phx-click="sort" phx-value-column="working_dir" role="button" tabindex="0">
                SANDBOX <i class={sort_icon_class("working_dir", @sort_column, @sort_order)} aria-hidden="true"></i>
              </th>
              <th class="sortable" phx-click="sort" phx-value-column="operating_system" role="button" tabindex="0">
                OS <i class={sort_icon_class("operating_system", @sort_column, @sort_order)} aria-hidden="true"></i>
              </th>
              <th class="sortable" phx-click="sort" phx-value-column="ipaddress" role="button" tabindex="0">
                IP ADDRESS <i class={sort_icon_class("ipaddress", @sort_column, @sort_order)} aria-hidden="true"></i>
              </th>
              <th class="sortable" phx-click="sort" phx-value-column="state" role="button" tabindex="0">
                STATUS <i class={sort_icon_class("state", @sort_column, @sort_order)} aria-hidden="true"></i>
              </th>
              <th class="sortable" phx-click="sort" phx-value-column="free_space" role="button" tabindex="0">
                FREE SPACE <i class={sort_icon_class("free_space", @sort_column, @sort_order)} aria-hidden="true"></i>
              </th>
              <th class="sortable" phx-click="sort" phx-value-column="resources" role="button" tabindex="0">
                RESOURCES <i class={sort_icon_class("resources", @sort_column, @sort_order)} aria-hidden="true"></i>
              </th>
              <th class="sortable" phx-click="sort" phx-value-column="environments" role="button" tabindex="0">
                ENVIRONMENTS <i class={sort_icon_class("environments", @sort_column, @sort_order)} aria-hidden="true"></i>
              </th>
            </tr>
          </thead>
          <tbody>
            <%= for agent <- displayed_agents(@agents, @agent_type, @filter, @sort_column, @sort_order) do %>
              <tr class={if agent.disabled, do: "disabled-row", else: ""}>
                <%= if @is_user_admin do %>
                  <td class="checkbox-cell">
                    <input
                      type="checkbox"
                      checked={MapSet.member?(@selected_agents, agent.uuid)}
                      phx-click="toggle_select"
                      phx-value-uuid={agent.uuid}
                    />
                  </td>
                <% end %>
                <td>
                  <%= if @is_user_admin do %>
                    <a
                      href={"/agents/#{agent.uuid}/job_run_history"}
                      title={agent.uuid}
                      class="agent-name"
                    >
                      {agent.hostname}
                    </a>
                  <% else %>
                    <span class="agent-name">{agent.hostname}</span>
                  <% end %>
                </td>
                <td>{agent.working_dir || ""}</td>
                <td>{agent.operating_system || ""}</td>
                <td>{agent.ipaddress}</td>
                <td>
                  <span class={status_class(Agents.effective_status(agent))}>
                    {status_text(Agents.effective_status(agent))}
                  </span>
                </td>
                <td>{format_bytes(agent.free_space)}</td>
                <td>
                  <%= if agent.resources && length(agent.resources) > 0 do %>
                    {Enum.join(agent.resources, ", ")}
                  <% else %>
                    <span class="none-specified">none specified</span>
                  <% end %>
                </td>
                <td>
                  <%= if agent.environments && length(agent.environments) > 0 do %>
                    {Enum.join(agent.environments, ", ")}
                  <% else %>
                    <span class="none-specified">none specified</span>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp fetch_agents do
    Agents.list_agents()
    |> Enum.reject(& &1.deleted)
  end

  defp filtered_agents(agents, :static) do
    Enum.reject(agents, &(&1.elastic_agent_id || &1.elastic_plugin_id))
  end

  defp filtered_agents(agents, :elastic) do
    Enum.filter(agents, &(&1.elastic_agent_id || &1.elastic_plugin_id))
  end

  defp displayed_agents(agents, type, filter, sort_column, sort_order) do
    agents
    |> filtered_agents(type)
    |> filter_by_search(filter)
    |> sort_agents(sort_column, sort_order)
  end

  defp filter_by_search(agents, ""), do: agents

  defp filter_by_search(agents, term) do
    term_lower = String.downcase(term)

    Enum.filter(agents, fn agent ->
      String.contains?(String.downcase(agent.hostname || ""), term_lower) or
        String.contains?(String.downcase(agent.ipaddress || ""), term_lower) or
        Enum.any?(agent.resources || [], &String.contains?(String.downcase(&1), term_lower)) or
        Enum.any?(agent.environments || [], &String.contains?(String.downcase(&1), term_lower))
    end)
  end

  defp sort_agents(agents, column, order) do
    Enum.sort_by(agents, fn agent -> sort_key(agent, column) end, order)
  end

  defp sort_key(agent, "hostname"), do: agent.hostname || ""
  defp sort_key(agent, "working_dir"), do: agent.working_dir || ""
  defp sort_key(agent, "operating_system"), do: agent.operating_system || ""
  defp sort_key(agent, "ipaddress"), do: agent.ipaddress || ""
  defp sort_key(agent, "state"), do: status_text(Agents.effective_status(agent))
  defp sort_key(agent, "free_space"), do: agent.free_space || 0
  defp sort_key(agent, "resources"), do: Enum.join(agent.resources || [], " ")
  defp sort_key(agent, "environments"), do: Enum.join(agent.environments || [], " ")
  defp sort_key(_agent, _), do: ""

  defp sort_icon_class(column, current_column, _order) when column != current_column, do: "fa fa-sort"
  defp sort_icon_class(_column, _current, :asc), do: "fa fa-sort-up"
  defp sort_icon_class(_column, _current, :desc), do: "fa fa-sort-down"

  defp total_count(agents, type) do
    length(filtered_agents(agents, type))
  end

  defp enabled_count(agents, type) do
    filtered_agents(agents, type)
    |> Enum.count(&(not &1.disabled))
  end

  defp disabled_count(agents, type) do
    filtered_agents(agents, type)
    |> Enum.count(& &1.disabled)
  end

  defp pending_count(_agents, _type) do
    # Agents in Pending config state (awaiting approval)
    0
  end

  defp pending_scheduled_count do
    if Process.whereis(ExGoCD.Scheduler), do: ExGoCD.Scheduler.pending_count(), else: 0
  end

  defp status_text(:disabled), do: "Disabled"
  defp status_text(:lost_contact), do: "LostContact"
  defp status_text(:building), do: "Building"
  defp status_text(:idle), do: "Idle"
  defp status_text(:unknown), do: "Unknown"

  defp status_class(:disabled), do: "status-disabled"
  defp status_class(:lost_contact), do: "status-lost-contact"
  defp status_class(:building), do: "status-building"
  defp status_class(:idle), do: "status-idle"
  defp status_class(:unknown), do: "status-unknown"

  defp format_bytes(nil), do: "Unknown"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  defp format_bytes(bytes) when bytes < 1024 * 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"

  defp return_forbidden(socket) do
    {:noreply, put_flash(socket, :error, "You are not authorized to perform this action.")}
  end
end
