defmodule SimpleOrgChart do
  @moduledoc """
  OrgHierarchy plugin: maps users to pipeline groups via a static org chart.
  Users inherit access to all pipeline groups in their org node and children.
  """

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
      %{id: "platform", name: "Platform Ops", pipeline_groups: ["infra", "deploy"], children: []}
    ]
  }

  @department_map %{
    "engineering" => ["frontend", "backend"],
    "platform" => ["infra", "deploy"]
  }

  def org_tree(_opts), do: @tree

  def pipeline_groups_for_user(user, _opts) do
    Map.get(@department_map, user_department(user), [])
  end

  def user_org_node(user, _opts) do
    find_node(@tree, user_department(user))
  end

  def ui_links, do: [{"Org Hierarchy", "/admin/security"}]

  defp user_department(user) do
    Map.get(user, :department) || Map.get(user, "department", "")
  end

  defp find_node(nil, _id), do: nil
  defp find_node(node, id) when node.id == id, do: {:ok, node}

  defp find_node(node, id) do
    Enum.find_value(node.children, &find_node(&1, id))
  end
end
