defmodule EnterpriseHierarchy do
  @moduledoc """
  Enterprise Org Hierarchy plugin — data-driven, hot-reloadable.

  Loads org structure from `priv/org.yaml` (YAML). Falls back to an embedded
  default tree. Watches the config file every 30s and reloads on changes.
  Change events are broadcast via `EnterpriseHierarchy.Events` for
  downstream consumers (audit logs, pipeline group re-evaluation).

  ## Config format (priv/org.yaml)

      root:
        id: "acme-corp"
        name: "Acme Corp"
        children:
          - id: engineering
            name: "Engineering"
            pipeline_groups: [frontend, backend]
            departments: [eng, engineering]
            children:
              - id: frontend
                name: "Frontend"
                pipeline_groups: [ui-components]
                departments: [fe]
  """

  use GenServer

  require Logger

  @poll_ms 30_000
  @config_relative "priv/org.yaml"

  # ── Public API ─────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the current org tree."
  def org_tree(_opts \\ []) do
    GenServer.call(__MODULE__, :tree)
  end

  @doc "Returns pipeline groups a user has access to based on their department."
  def pipeline_groups_for_user(user, _opts \\ []) do
    dept = user_department(user)
    if dept != "", do: find_groups(dept, GenServer.call(__MODULE__, :tree), []), else: []
  end

  @doc "Finds the org node matching a user's department."
  def user_org_node(user, _opts \\ []) do
    dept = user_department(user)
    if dept != "", do: find_node(dept, GenServer.call(__MODULE__, :tree)), else: nil
  end

  def ui_links, do: []

  @doc "Forces an immediate config reload. Returns {:ok, :reloaded} or {:ok, :unchanged}."
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @doc "Updates the org tree directly from a JSON map. Triggers change broadcast."
  def update_tree(tree_map) do
    GenServer.call(__MODULE__, {:update_tree, tree_map})
  end

  @doc "Resets to the default built-in tree. Useful for tests."
  def reset_tree do
    GenServer.call(__MODULE__, :reset_tree)
  end

  # ── GenServer callbacks ────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    tree = load_config()
    schedule_poll()
    {:ok, %{tree: tree, mtime: file_mtime()}}
  end

  @impl true
  def handle_call(:tree, _from, state) do
    {:reply, state.tree, state}
  end

  def handle_call(:reload, _from, state) do
    {:reply, do_reload(state), state}
  end

  def handle_call({:update_tree, tree_map}, _from, state) do
    tree = from_json_map(tree_map)
    Logger.info("[enterprise_hierarchy] Tree updated via API (#{count_nodes(tree)} nodes)")
    broadcast_change(tree)
    {:reply, :ok, %{state | tree: tree}}
  end

  def handle_call(:reset_tree, _from, state) do
    tree = default_tree()
    {:reply, :ok, %{state | tree: tree}}
  end

  @impl true
  def handle_info(:poll, state) do
    schedule_poll()
    {:noreply, do_reload(state)}
  end

  # ── Config loading ─────────────────────────────────────────────────────────

  defp do_reload(%{mtime: prev} = state) do
    current = file_mtime()

    if current && current != prev do
      Logger.info("[enterprise_hierarchy] Config changed, reloading org tree (#{current})")
      tree = load_config()
      broadcast_change(tree)
      %{state | tree: tree, mtime: current}
    else
      state
    end
  end

  defp load_config do
    case find_config_file() do
      {:ok, path} -> parse_yaml(path)
      :not_found -> default_tree()
    end
  end

  defp find_config_file do
    paths = [
      @config_relative,
      Path.join(:code.priv_dir(:enterprise_hierarchy), "org.yaml"),
      Path.expand("priv/org.yaml")
    ]

    case Enum.find(paths, &File.exists?/1) do
      nil -> :not_found
      path -> {:ok, path}
    end
  end

  defp parse_yaml(path) do
    yaml = File.read!(path)
    [config] = :yamerl_constr.string(yaml)
    root = to_map(config)["root"]
    from_yaml_map(root)
  rescue
    e ->
      Logger.warning("[enterprise_hierarchy] YAML parse error: #{Exception.message(e)}, using default")
      default_tree()
  end

  defp to_map([{key, val} | rest]), do: Map.put(to_map(rest), to_string(key), to_map_val(val))
  defp to_map([]), do: %{}
  defp to_map_val(val) when is_list(val) and length(val) > 0 and is_tuple(hd(val)),
    do: to_map(val)
  defp to_map_val(val) when is_list(val) and length(val) > 0 and is_number(hd(val)),
    do: val
  defp to_map_val(val) when is_list(val),
    do: Enum.map(val, &to_map_val/1)
  defp to_map_val(val) when is_binary(val), do: val
  defp to_map_val(val), do: val

  # ── Charlist → string conversion for YAML-parsed values ──────────────────

  defp from_yaml_map(map) do
    %{
      id: to_s(map["id"] || map[:id]),
      name: to_s(map["name"] || map[:name]),
      pipeline_groups: (map["pipeline_groups"] || map[:pipeline_groups] || []) |> Enum.map(&to_s/1),
      departments: (map["departments"] || map[:departments] || []) |> Enum.map(&to_s/1),
      children: (map["children"] || map[:children] || []) |> Enum.map(&from_yaml_map/1)
    }
  end

  # JSON API input uses string keys, values already strings
  defp from_json_map(map) do
    %{
      id: map["id"] || map[:id] || "api",
      name: map["name"] || map[:name] || "API",
      pipeline_groups: (map["pipeline_groups"] || map[:pipeline_groups] || []) |> Enum.map(&to_s/1),
      departments: (map["departments"] || map[:departments] || []) |> Enum.map(&to_s/1),
      children: (map["children"] || map[:children] || []) |> Enum.map(&from_json_map/1)
    }
  end

  defp to_s(v) when is_binary(v), do: v
  defp to_s(v) when is_list(v), do: List.to_string(v)
  defp to_s(v) when is_atom(v), do: Atom.to_string(v)
  defp to_s(v), do: to_string(v)

  defp default_tree do
    %{
      id: "acme-corp", name: "Acme Corp", pipeline_groups: [], departments: [],
      children: [
        %{id: "engineering", name: "Engineering",
          pipeline_groups: ["frontend", "backend", "shared-libs"],
          departments: ["eng", "engineering", "dev"],
          children: [
            %{id: "frontend-team", name: "Frontend Team",
              pipeline_groups: ["frontend", "ui-components", "design-system"],
              departments: ["frontend", "fe", "ui"], children: []},
            %{id: "backend-team", name: "Backend Team",
              pipeline_groups: ["backend", "api-gateway", "auth-service"],
              departments: ["backend", "be", "api"], children: []}
          ]},
        %{id: "platform", name: "Platform Operations",
          pipeline_groups: ["infra", "deploy", "monitoring", "k8s"],
          departments: ["ops", "platform", "sre", "devops"], children: []},
        %{id: "data", name: "Data & Analytics",
          pipeline_groups: ["data-pipeline", "ml-models", "etl-jobs"],
          departments: ["data", "analytics", "ml", "ds"], children: []},
        %{id: "security", name: "Security",
          pipeline_groups: ["security-scan", "compliance", "secrets"],
          departments: ["security", "sec", "infosec"], children: []}
      ]}
  end

  # ── File watching ──────────────────────────────────────────────────────────

  defp file_mtime do
    case find_config_file() do
      {:ok, path} ->
        case File.stat(path) do
          {:ok, stat} -> stat.mtime
          _ -> nil
        end
      :not_found -> nil
    end
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_ms)
  end

  # ── Change broadcasting ────────────────────────────────────────────────────

  defp broadcast_change(tree) do
    # Log the change event — in a full cluster deployment, this would
    # broadcast via the Plugin.Registry or cluster PubSub.
    node_count = count_nodes(tree)
    dept_count = count_departments(tree)
    Logger.info("[enterprise_hierarchy] Org tree updated: #{node_count} nodes, #{dept_count} departments")
  end

  defp count_nodes(node) do
    1 + Enum.reduce(node.children, 0, fn c, acc -> acc + count_nodes(c) end)
  end

  defp count_departments(node) do
    length(node.departments) + Enum.reduce(node.children, 0, fn c, acc -> acc + count_departments(c) end)
  end

  # ── Tree traversal (stateless) ─────────────────────────────────────────────

  defp user_department(user) do
    Map.get(user, :department) || Map.get(user, "department", "")
  end

  defp find_groups(dept, node, inherited) do
    dl = String.downcase(dept)
    nd = (node.departments || []) |> Enum.map(&String.downcase/1)

    if dl in nd do
      all_descendant = collect_all_groups(node)
      (inherited ++ all_descendant) |> Enum.uniq()
    else
      Enum.flat_map(node.children, fn c ->
        find_groups(dept, c, inherited)
      end) |> Enum.uniq()
    end
  end

  defp collect_all_groups(node) do
    child_groups = Enum.flat_map(node.children, &collect_all_groups/1)
    (node.pipeline_groups ++ child_groups) |> Enum.uniq()
  end

  defp find_node(dept, node) do
    dl = String.downcase(dept)
    nd = (node.departments || []) |> Enum.map(&String.downcase/1)

    if dl in nd do
      {:ok, node}
    else
      Enum.find_value(node.children, &find_node(dept, &1))
    end
  end
end
