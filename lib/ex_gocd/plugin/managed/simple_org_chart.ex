defmodule ExGoCD.Plugin.Managed.SimpleOrgChart do
  @moduledoc """
  Example OrgHierarchy plugin: maps users to pipeline groups via a static
  org chart. Users inherit access to all pipeline groups in their org node
  and its children.

  Configure:

      config :ex_gocd, :plugins,
        org_hierarchy: ExGoCD.Plugin.Managed.SimpleOrgChart
  """

  @behaviour ExGoCD.Plugin.OrgHierarchy

  @tree %{
    id: "root",
    name: "Acme Corp",
    pipeline_groups: [],
    children: [
      %{
        id: "engineering",
        name: "Engineering",
        pipeline_groups: ["frontend", "backend"],
        children: []
      },
      %{
        id: "platform",
        name: "Platform Ops",
        pipeline_groups: ["infra", "deploy"],
        children: []
      }
    ]
  }

  # Map user departments (from user metadata) to org nodes
  @department_map %{
    "engineering" => ["frontend", "backend"],
    "platform" => ["infra", "deploy"]
  }

  @impl true
  def org_tree(_opts), do: @tree

  @impl true
  def pipeline_groups_for_user(user, _opts) do
    dept = user_department(user)
    Map.get(@department_map, dept, [])
  end

  @impl true
  def user_org_node(user, _opts) do
    dept = user_department(user)
    find_node(@tree, dept)
  end

  defp user_department(user) do
    Map.get(user, :department) || Map.get(user, "department", "")
  end

  defp find_node(nil, _id), do: nil

  defp find_node(node, id) when node.id == id, do: {:ok, node}

  defp find_node(node, id) do
    Enum.find_value(node.children, &find_node(&1, id))
  end
end
