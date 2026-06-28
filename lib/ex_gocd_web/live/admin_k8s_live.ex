defmodule ExGoCDWeb.AdminK8sLive do
  @moduledoc """
  Admin tab for Kubernetes Elastic Agent configuration.

  Manages:
  - Cluster Profiles: K8s API connection (server URL, token, CA cert, namespace)
  - Elastic Agent Profiles: pod spec (image, memory, CPU, env vars, service account,
    node selector, pod annotations)

  UX mirrors GoCD's kubernetes-elastic-agents plugin but with a modern LiveView
  form-based interface instead of JSON text fields.
  """
  use ExGoCDWeb, :live_view

  alias ExGoCD.ClusterProfiles
  alias ExGoCD.ElasticAgentProfiles
  alias ExGoCD.ClusterProfiles.ClusterProfile
  alias ExGoCD.ElasticAgentProfiles.ElasticAgentProfile

  @compile {:nowarn_unused_function,
            [{:safe_check, 1}, {:connection_status_badge, 1}, {:get_conn_status, 2}]}

  @impl true
  def mount(_params, _session, socket) do
    k3s_status = ClusterProfiles.maybe_auto_seed_k3s()
    profiles = ClusterProfiles.list_profiles()

    socket =
      assign(socket,
        page_title: "Elastic Agents",
        active_tab: "elastic_agents",
        cluster_profiles: profiles,
        agent_profiles: ElasticAgentProfiles.list_profiles(),
        show_cluster_modal: false,
        show_agent_modal: false,
        editing_cluster: nil,
        editing_agent: nil,
        cluster_form: empty_cluster_form(),
        agent_form: empty_agent_form(),
        k3s_status: k3s_status,
        show_token: %{},
        connection_status: %{}
      )

    # Start async connectivity checks for each cluster profile
    socket =
      Enum.reduce(profiles, socket, fn profile, acc ->
        try do
          start_async(acc, {:check_conn, profile.id}, fn ->
            {profile.id, ClusterProfiles.check_connection(profile)}
          end)
        rescue
          _ -> acc
        end
      end)

    {:ok, socket}
  end

  @impl true
  def handle_async({:check_conn, id}, {:ok, {id, status}}, socket) do
    {:noreply,
     put_in(
       socket.assigns.connection_status,
       Map.put(socket.assigns.connection_status, id, status)
     )}
  end

  @impl true
  def handle_async({:check_conn, id}, {:exit, reason}, socket) do
    msg =
      case reason do
        %{__struct__: _} -> Exception.message(reason)
        other -> inspect(other)
      end

    status_map = Map.get(socket.assigns, :connection_status, %{})
    {:noreply, assign(socket, :connection_status, Map.put(status_map, id, {:error, msg}))}
  end

  # Catch-all — never crash on unexpected async results
  def handle_async({:check_conn, id}, unexpected, socket) do
    status_map = Map.get(socket.assigns, :connection_status, %{})
    {:noreply, assign(socket, :connection_status, Map.put(status_map, id, {:error, "Unexpected: #{inspect(unexpected)}"}))}
  end

  # ── Cluster Profile actions ───────────────────────────────────────────────

  @impl true
  def handle_event("open_cluster_modal", %{"id" => id}, socket) do
    profile = ClusterProfiles.get_profile!(id)

    {:noreply,
     assign(socket,
       show_cluster_modal: true,
       editing_cluster: profile,
       cluster_form: cluster_to_form(profile)
     )}
  end

  def handle_event("open_cluster_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_cluster_modal: true,
       editing_cluster: nil,
       cluster_form: empty_cluster_form()
     )}
  end

  def handle_event("close_cluster_modal", _params, socket) do
    {:noreply, assign(socket, show_cluster_modal: false, editing_cluster: nil)}
  end

  def handle_event("auto_parse_kubeconfig", %{"cluster" => %{"kubeconfig_yaml" => yaml}}, socket)
      when is_binary(yaml) and yaml != "" do
    case ExGoCD.K8s.extract_k3s_config(yaml) do
      {:ok, config} ->
        current = socket.assigns.cluster_form
        form_data = Map.put(current.data || %{}, :server_url, config["server"])
        form_data = Map.put(form_data, :bearer_token, config["token"])
        form_data = Map.put(form_data, :ca_cert, config["ca_cert"])
        form_data = Map.put(form_data, :namespace, config["namespace"])
        form_data = Map.put(form_data, :client_cert, config["client_cert"])
        form_data = Map.put(form_data, :client_key, config["client_key"])
        form_data = Map.put(form_data, :kubeconfig_parsed, true)

        changeset =
          %ClusterProfile{}
          |> ClusterProfile.changeset(normalize_cluster_params(form_data))
          |> Map.put(:action, :validate)

        {:noreply, assign(socket, cluster_form: to_form(changeset))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("auto_parse_kubeconfig", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_cluster", %{"cluster" => params}, socket) do
    changeset =
      %ClusterProfile{}
      |> ClusterProfile.changeset(normalize_cluster_params(params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, cluster_form: to_form(changeset))}
  end

  def handle_event("save_cluster", %{"cluster" => params}, socket) do
    attrs = normalize_cluster_params(params)

    result =
      case socket.assigns.editing_cluster do
        nil -> ClusterProfiles.create_profile(attrs)
        profile -> ClusterProfiles.update_profile(profile, attrs)
      end

    case result do
      {:ok, profile} ->
        profiles = ClusterProfiles.list_profiles()

        socket =
          socket
          |> assign(
            show_cluster_modal: false,
            editing_cluster: nil,
            cluster_profiles: profiles,
            agent_profiles: ElasticAgentProfiles.list_profiles()
          )
          |> put_flash(:info, "Cluster profile saved.")

        # Re-check connection for the saved/updated profile
        socket =
          try do
            start_async(socket, {:check_conn, profile.id}, fn ->
              {profile.id, ClusterProfiles.check_connection(profile)}
            end)
          rescue
            _ -> socket
          end

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, cluster_form: to_form(changeset))}
    end
  end

  def handle_event("delete_cluster", %{"id" => id}, socket) do
    profile = ClusterProfiles.get_profile!(id)
    ClusterProfiles.delete_profile(profile)

    {:noreply,
     socket
     |> assign(
       cluster_profiles: ClusterProfiles.list_profiles(),
       agent_profiles: ElasticAgentProfiles.list_profiles()
     )
     |> put_flash(:info, "Cluster profile deleted.")}
  end

  def handle_event("recheck_cluster", %{"id" => id}, socket) do
    # Mark as checking
    socket =
      put_in(socket.assigns.connection_status, Map.put(socket.assigns.connection_status, id, nil))

    case ClusterProfiles.get_profile(id) do
      nil ->
        {:noreply, socket}

      profile ->
        start_async(socket, {:check_conn, id}, fn ->
          {id, ClusterProfiles.check_connection(profile)}
        end)
        |> then(&{:noreply, &1})
    end
  end

  # ── Elastic Agent Profile actions ─────────────────────────────────────────

  @impl true
  def handle_event("open_agent_modal", %{"id" => id}, socket) do
    profile = ElasticAgentProfiles.get_profile!(id)

    {:noreply,
     assign(socket,
       show_agent_modal: true,
       editing_agent: profile,
       agent_form: agent_to_form(profile)
     )}
  end

  def handle_event("open_agent_modal", _params, socket) do
    {:noreply,
     assign(socket, show_agent_modal: true, editing_agent: nil, agent_form: empty_agent_form())}
  end

  def handle_event("close_agent_modal", _params, socket) do
    {:noreply, assign(socket, show_agent_modal: false, editing_agent: nil)}
  end

  def handle_event("validate_agent", %{"agent" => params}, socket) do
    changeset =
      %ElasticAgentProfile{}
      |> ElasticAgentProfile.changeset(normalize_agent_params(params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, agent_form: to_form(changeset))}
  end

  def handle_event("save_agent", %{"agent" => params}, socket) do
    attrs = normalize_agent_params(params)

    result =
      case socket.assigns.editing_agent do
        nil -> ElasticAgentProfiles.create_profile(attrs)
        profile -> ElasticAgentProfiles.update_profile(profile, attrs)
      end

    case result do
      {:ok, _profile} ->
        {:noreply,
         socket
         |> assign(
           show_agent_modal: false,
           editing_agent: nil,
           agent_profiles: ElasticAgentProfiles.list_profiles()
         )
         |> put_flash(:info, "Elastic agent profile saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, agent_form: to_form(changeset))}
    end
  end

  def handle_event("delete_agent", %{"id" => id}, socket) do
    profile = ElasticAgentProfiles.get_profile!(id)
    ElasticAgentProfiles.delete_profile(profile)

    {:noreply,
     socket
     |> assign(agent_profiles: ElasticAgentProfiles.list_profiles())
     |> put_flash(:info, "Agent profile deleted.")}
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-2xl font-bold mb-6">⚡ Elastic Agents</h1>

      <%!-- Flash messages --%>
      <div
        :if={Phoenix.Flash.get(@flash, :info)}
        class="mb-4 p-3 bg-green-50 border border-green-200 rounded text-green-800"
      >
        {Phoenix.Flash.get(@flash, :info)}
      </div>

      <%!-- K3s auto-discovery status --%>
      <div
        :if={assigns[:k3s_status] == :ok}
        class="mb-4 p-3 bg-blue-50 border border-blue-200 rounded text-blue-800 text-sm"
      >
        🖥️ Local k3s cluster detected — "k3s-local" profile auto-configured.
      </div>
      <div
        :if={assigns[:k3s_status] == :no_k3s}
        class="mb-4 p-3 bg-amber-50 border border-amber-200 rounded text-amber-800 text-sm"
      >
        ℹ️ No local k3s detected. Add a cluster profile manually or start k3s via <code class="bg-amber-100 px-1 rounded">docker compose up k3s</code>.
      </div>

      <%!-- Cluster Profiles Section --%>
      <section class="mb-8">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-xl font-semibold">Cluster Profiles</h2>
          <button
            phx-click="open_cluster_modal"
            class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 text-sm"
          >
            + Add Cluster
          </button>
        </div>

        <div :if={Enum.empty?(@cluster_profiles)} class="text-gray-500 italic p-4 border rounded">
          No cluster profiles yet. Add a Kubernetes cluster connection to enable elastic agents.
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%= for profile <- @cluster_profiles do %>
            <div class="border rounded-lg p-4 hover:shadow-md transition-shadow">
              <div class="flex justify-between items-start mb-2">
                <h3 class="font-semibold text-lg">{profile.name || "Unnamed"}</h3>
                <span class="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded">
                  {profile.plugin_id}
                </span>
              </div>
              <div class="text-sm text-gray-600 space-y-1">
                <div>
                  <span class="font-medium">Server:</span> {ClusterProfile.server_url(profile) || "—"}
                </div>
                <div>
                  <span class="font-medium">Namespace:</span> {ClusterProfile.namespace(profile)}
                </div>
                <div>
                  <span class="font-medium">Token:</span>
                  <%= if ClusterProfile.client_cert(profile) && ClusterProfile.client_key(profile) do %>
                    ✓ Client certificate
                  <% else %>
                    {if ClusterProfile.bearer_token(profile), do: "✓ Configured", else: "✗ Missing"}
                  <% end %>
                </div>
                <div class="mt-2">
                  {connection_status_badge(get_conn_status(assigns, profile.id))}
                </div>
              </div>
              <div class="flex gap-2 mt-3">
                <button
                  phx-click="open_cluster_modal"
                  phx-value-id={profile.id}
                  class="text-sm text-blue-600 hover:underline"
                >
                  Edit
                </button>
                <button
                  phx-click="recheck_cluster"
                  phx-value-id={profile.id}
                  class="text-sm text-gray-600 hover:underline"
                >
                  Re-check
                </button>
                <button
                  phx-click="delete_cluster"
                  phx-value-id={profile.id}
                  phx-confirm="Delete this cluster profile?"
                  class="text-sm text-red-600 hover:underline"
                >
                  Delete
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </section>

      <%!-- Elastic Agent Profiles Section --%>
      <section>
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-xl font-semibold">Elastic Agent Profiles</h2>
          <button
            :if={!Enum.empty?(@cluster_profiles)}
            phx-click="open_agent_modal"
            class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 text-sm"
          >
            + Add Agent Profile
          </button>
        </div>

        <div :if={Enum.empty?(@agent_profiles)} class="text-gray-500 italic p-4 border rounded">
          No elastic agent profiles yet. Add one to define the pod template for elastic agents.
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%= for profile <- @agent_profiles do %>
            <div class="border rounded-lg p-4 hover:shadow-md transition-shadow">
              <div class="flex justify-between items-start mb-2">
                <h3 class="font-semibold text-lg">{profile.name || "Unnamed"}</h3>
                <span class="text-xs bg-green-100 text-green-800 px-2 py-1 rounded">k8s-agent</span>
              </div>
              <div class="text-sm text-gray-600 space-y-1">
                <div>
                  <span class="font-medium">Image:</span> {ElasticAgentProfile.image(profile)}
                </div>
                <div>
                  <span class="font-medium">Memory:</span> {ElasticAgentProfile.min_memory(profile)} → {ElasticAgentProfile.max_memory(
                    profile
                  )}
                </div>
                <div>
                  <span class="font-medium">CPU:</span> {ElasticAgentProfile.min_cpu(profile)} → {ElasticAgentProfile.max_cpu(
                    profile
                  )}
                </div>
                <div>
                  <span class="font-medium">Pull Policy:</span> {ElasticAgentProfile.image_pull_policy(
                    profile
                  )}
                </div>
                <div>
                  <span class="font-medium">Privileged:</span> {ElasticAgentProfile.privileged(
                    profile
                  )}
                </div>
              </div>
              <div class="flex gap-2 mt-3">
                <button
                  phx-click="open_agent_modal"
                  phx-value-id={profile.id}
                  class="text-sm text-blue-600 hover:underline"
                >
                  Edit
                </button>
                <button
                  phx-click="delete_agent"
                  phx-value-id={profile.id}
                  phx-confirm="Delete this agent profile?"
                  class="text-sm text-red-600 hover:underline"
                >
                  Delete
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </section>

      <%!-- Cluster Profile Modal --%>
      <div
        :if={@show_cluster_modal}
        class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
        phx-click-away="close_cluster_modal"
        phx-key="Escape"
        phx-key-action="close_cluster_modal"
      >
        <div class="bg-white rounded-lg p-6 w-full max-w-lg max-h-[80vh] overflow-y-auto shadow-xl">
          <h2 class="text-lg font-bold mb-4">
            {if @editing_cluster, do: "Edit", else: "Add"} Cluster Profile
          </h2>

          <.form
            for={@cluster_form}
            phx-change="validate_cluster"
            phx-submit="save_cluster"
            class="space-y-4"
          >
            <div>
              <label class="block text-sm font-medium mb-1">Name *</label>
              <input
                type="text"
                name="cluster[name]"
                value={@cluster_form[:name].value}
                class="w-full border rounded px-3 py-2"
                placeholder="my-k8s-cluster"
                required
              />
              <div :if={@cluster_form[:name].errors} class="text-red-600 text-sm mt-1">
                {for err <- @cluster_form[:name].errors, do: err}
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Kubernetes API Server URL *</label>
              <input
                type="text"
                name="cluster[server_url]"
                value={@cluster_form[:server_url].value}
                class="w-full border rounded px-3 py-2 font-mono text-sm"
                placeholder="https://k8s.example.com:6443"
              />
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Bearer Token</label>
              <input
                type="password"
                name="cluster[bearer_token]"
                value={@cluster_form[:bearer_token].value}
                class="w-full border rounded px-3 py-2 font-mono text-sm"
                placeholder="eyJhbGciOi..."
              />
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">CA Certificate (PEM)</label>
              <textarea
                name="cluster[ca_cert]"
                rows="3"
                class="w-full border rounded px-3 py-2 font-mono text-xs"
                placeholder="-----BEGIN CERTIFICATE-----&#10;...&#10;-----END CERTIFICATE-----"
              ><%= @cluster_form[:ca_cert].value %></textarea>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Namespace</label>
              <input
                type="text"
                name="cluster[namespace]"
                value={@cluster_form[:namespace].value}
                class="w-full border rounded px-3 py-2"
                placeholder="default"
              />
            </div>

            <div class="flex justify-end gap-2 pt-4">
              <button
                type="button"
                phx-click="close_cluster_modal"
                class="px-4 py-2 border rounded hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
              >
                Save
              </button>
            </div>
          </.form>
        </div>
      </div>

      <%!-- Elastic Agent Profile Modal --%>
      <div
        :if={@show_agent_modal}
        class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
        phx-click-away="close_agent_modal"
        phx-key="Escape"
        phx-key-action="close_agent_modal"
      >
        <div class="bg-white rounded-lg p-6 w-full max-w-lg max-h-[80vh] overflow-y-auto shadow-xl">
          <h2 class="text-lg font-bold mb-4">
            {if @editing_agent, do: "Edit", else: "Add"} Elastic Agent Profile
          </h2>

          <.form
            for={@agent_form}
            phx-change="validate_agent"
            phx-submit="save_agent"
            class="space-y-4"
          >
            <div>
              <label class="block text-sm font-medium mb-1">Profile Name *</label>
              <input
                type="text"
                name="agent[name]"
                value={@agent_form[:name].value}
                class="w-full border rounded px-3 py-2"
                placeholder="docker-agent"
                required
              />
              <div :if={@agent_form[:name].errors} class="text-red-600 text-sm mt-1">
                {for err <- @agent_form[:name].errors, do: err}
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Cluster Profile *</label>
              <select
                name="agent[cluster_profile_id]"
                class="w-full border rounded px-3 py-2"
                required
              >
                <option value="">Select a cluster...</option>
                <%= for cp <- @cluster_profiles do %>
                  <option value={cp.id} selected={@agent_form[:cluster_profile_id].value == cp.id}>
                    {cp.name || cp.id}
                  </option>
                <% end %>
              </select>
              <div :if={@agent_form[:cluster_profile_id].errors} class="text-red-600 text-sm mt-1">
                {for err <- @agent_form[:cluster_profile_id].errors, do: err}
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Docker Image *</label>
              <input
                type="text"
                name="agent[image]"
                value={@agent_form[:image].value}
                class="w-full border rounded px-3 py-2 font-mono text-sm"
                placeholder="gocd/gocd-agent-docker-24.5.0"
              />
            </div>

            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium mb-1">Min Memory</label>
                <input
                  type="text"
                  name="agent[min_memory]"
                  value={@agent_form[:min_memory].value}
                  class="w-full border rounded px-3 py-2"
                  placeholder="1Gi"
                />
              </div>
              <div>
                <label class="block text-sm font-medium mb-1">Max Memory</label>
                <input
                  type="text"
                  name="agent[max_memory]"
                  value={@agent_form[:max_memory].value}
                  class="w-full border rounded px-3 py-2"
                  placeholder="2Gi"
                />
              </div>
            </div>

            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium mb-1">Min CPU</label>
                <input
                  type="text"
                  name="agent[min_cpu]"
                  value={@agent_form[:min_cpu].value}
                  class="w-full border rounded px-3 py-2"
                  placeholder="1"
                />
              </div>
              <div>
                <label class="block text-sm font-medium mb-1">Max CPU</label>
                <input
                  type="text"
                  name="agent[max_cpu]"
                  value={@agent_form[:max_cpu].value}
                  class="w-full border rounded px-3 py-2"
                  placeholder="2"
                />
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Image Pull Policy</label>
              <select name="agent[image_pull_policy]" class="w-full border rounded px-3 py-2">
                <option
                  value="IfNotPresent"
                  selected={@agent_form[:image_pull_policy].value == "IfNotPresent"}
                >
                  IfNotPresent
                </option>
                <option value="Always" selected={@agent_form[:image_pull_policy].value == "Always"}>
                  Always
                </option>
                <option value="Never" selected={@agent_form[:image_pull_policy].value == "Never"}>
                  Never
                </option>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Privileged</label>
              <select name="agent[privileged]" class="w-full border rounded px-3 py-2">
                <option value="false" selected={@agent_form[:privileged].value == "false"}>No</option>
                <option value="true" selected={@agent_form[:privileged].value == "true"}>Yes</option>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">
                Environment Variables (one per line, KEY=VALUE)
              </label>
              <textarea
                name="agent[env_vars_text]"
                rows="3"
                class="w-full border rounded px-3 py-2 font-mono text-xs"
                placeholder="GO_SERVER_URL=http://host.docker.internal:8153/go&#10;JAVA_HOME=/usr/lib/jvm/java-21"
              ><%= @agent_form[:env_vars_text].value %></textarea>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Service Account</label>
              <input
                type="text"
                name="agent[service_account]"
                value={@agent_form[:service_account].value}
                class="w-full border rounded px-3 py-2"
                placeholder="gocd-agent-sa"
              />
              <p class="text-xs text-gray-500 mt-1">
                Kubernetes service account for the agent pod. Leave empty to use the namespace default.
              </p>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">
                Node Selector (one per line, KEY=VALUE)
              </label>
              <textarea
                name="agent[node_selector_text]"
                rows="2"
                class="w-full border rounded px-3 py-2 font-mono text-xs"
                placeholder="node-type=ci&#10;disk=ssd"
              ><%= @agent_form[:node_selector_text].value %></textarea>
              <p class="text-xs text-gray-500 mt-1">
                Kubernetes node selector labels to constrain which nodes the pod runs on.
              </p>
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">
                Pod Annotations (one per line, KEY=VALUE)
              </label>
              <textarea
                name="agent[pod_annotations_text]"
                rows="2"
                class="w-full border rounded px-3 py-2 font-mono text-xs"
                placeholder="sidecar.istio.io/inject=false&#10;team=platform"
              ><%= @agent_form[:pod_annotations_text].value %></textarea>
              <p class="text-xs text-gray-500 mt-1">
                Kubernetes annotations added to the agent pod metadata.
              </p>
            </div>

            <div class="flex justify-end gap-2 pt-4">
              <button
                type="button"
                phx-click="close_agent_modal"
                class="px-4 py-2 border rounded hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
              >
                Save
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp empty_cluster_form do
    %ClusterProfile{}
    |> ClusterProfile.changeset(%{})
    |> to_form()
  end

  defp empty_agent_form do
    %ElasticAgentProfile{}
    |> ElasticAgentProfile.changeset(%{})
    |> to_form()
  end

  defp cluster_to_form(profile) do
    profile
    |> Map.put(:server_url, ClusterProfile.server_url(profile))
    |> Map.put(:bearer_token, ClusterProfile.bearer_token(profile))
    |> Map.put(:ca_cert, ClusterProfile.ca_cert(profile))
    |> Map.put(:namespace, ClusterProfile.namespace(profile))
    |> ClusterProfile.changeset(%{})
    |> to_form()
  end

  defp agent_to_form(profile) do
    profile
    |> Map.put(:image, ElasticAgentProfile.image(profile))
    |> Map.put(:min_memory, ElasticAgentProfile.min_memory(profile))
    |> Map.put(:max_memory, ElasticAgentProfile.max_memory(profile))
    |> Map.put(:min_cpu, ElasticAgentProfile.min_cpu(profile))
    |> Map.put(:max_cpu, ElasticAgentProfile.max_cpu(profile))
    |> Map.put(:image_pull_policy, ElasticAgentProfile.image_pull_policy(profile))
    |> Map.put(:privileged, ElasticAgentProfile.privileged(profile))
    |> Map.put(:env_vars_text, format_env_vars(ElasticAgentProfile.env_vars(profile)))
    |> Map.put(:service_account, ElasticAgentProfile.service_account(profile))
    |> Map.put(:node_selector_text, format_key_value(ElasticAgentProfile.node_selector(profile)))
    |> Map.put(
      :pod_annotations_text,
      format_key_value(ElasticAgentProfile.pod_annotations(profile))
    )
    |> ElasticAgentProfile.changeset(%{})
    |> to_form()
  end

  defp normalize_cluster_params(params) do
    props = %{
      "kubernetes_cluster_url" => Map.get(params, "server_url"),
      "bearer_token" => Map.get(params, "bearer_token"),
      "kubernetes_cluster_ca_cert" => Map.get(params, "ca_cert"),
      "namespace" => Map.get(params, "namespace", "default")
    }

    %{
      name: Map.get(params, "name"),
      plugin_id: "ex_gocd.elasticagent.kubernetes",
      properties: props
    }
  end

  defp normalize_agent_params(params) do
    env_vars =
      (params["env_vars_text"] || "")
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn line ->
        case String.split(line, "=", parts: 2) do
          [k, v] -> %{"name" => String.trim(k), "value" => String.trim(v)}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    node_selector =
      (params["node_selector_text"] || "")
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, "=", parts: 2) do
          [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
          _ -> acc
        end
      end)

    pod_annotations =
      (params["pod_annotations_text"] || "")
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, "=", parts: 2) do
          [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
          _ -> acc
        end
      end)

    props = %{
      "Image" => Map.get(params, "image", "gocd/gocd-agent-docker-24.5.0"),
      "MaxMemory" => Map.get(params, "max_memory", "2Gi"),
      "MaxCPU" => Map.get(params, "max_cpu", "2"),
      "MinMemory" => Map.get(params, "min_memory", "1Gi"),
      "MinCPU" => Map.get(params, "min_cpu", "1"),
      "ImagePullPolicy" => Map.get(params, "image_pull_policy", "IfNotPresent"),
      "Privileged" => Map.get(params, "privileged", "false"),
      "Environment" => env_vars,
      "ServiceAccount" => Map.get(params, "service_account", ""),
      "NodeSelector" => node_selector,
      "PodAnnotations" => pod_annotations
    }

    %{
      name: Map.get(params, "name"),
      plugin_id: "ex_gocd.elasticagent.kubernetes",
      cluster_profile_id: Map.get(params, "cluster_profile_id"),
      properties: props
    }
  end

  defp format_env_vars(env_vars) when is_list(env_vars) do
    Enum.map_join(env_vars, "\n", fn
      %{"name" => k, "value" => v} -> "#{k}=#{v}"
      %{name: k, value: v} -> "#{k}=#{v}"
      _ -> ""
    end)
  end

  defp format_env_vars(_), do: ""

  defp format_key_value(map) when is_map(map) do
    Enum.map_join(map, "\n", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp format_key_value(_), do: ""

  # ── Connection status helpers ──────────────────────────────────────────────

  defp get_conn_status(assigns, profile_id) do
    Map.get(assigns, :connection_status, %{}) |> Map.get(profile_id)
  end

  defp connection_status_badge(nil) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center gap-1 text-xs text-gray-500">
      <span class="w-2 h-2 bg-gray-300 rounded-full animate-pulse"></span>
      Checking\u2026
    </span>\
    """)
  end

  defp connection_status_badge(:ok) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center gap-1 text-xs text-green-700" title="Cluster is reachable">
      <span class="w-2 h-2 bg-green-500 rounded-full"></span>
      Connected
    </span>\
    """)
  end

  defp connection_status_badge({:error, :incomplete}) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center gap-1 text-xs text-amber-700" title="Missing server URL or token">
      <span class="w-2 h-2 bg-amber-400 rounded-full"></span>
      Incomplete \u2014 configure server and token
    </span>\
    """)
  end

  defp connection_status_badge({:error, reason}) when is_binary(reason) do
    escaped = Phoenix.HTML.html_escape(reason) |> Phoenix.HTML.safe_to_string()

    Phoenix.HTML.raw("""
    <span class="inline-flex items-center gap-1 text-xs text-red-700" title="#{escaped}">
      <span class="w-2 h-2 bg-red-500 rounded-full"></span>
      Failed \u2014 #{escaped}
    </span>\
    """)
  end

  defp connection_status_badge(_) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center gap-1 text-xs text-gray-500">
      <span class="w-2 h-2 bg-gray-300 rounded-full"></span>
      Unknown
    </span>\
    """)
  end
end
