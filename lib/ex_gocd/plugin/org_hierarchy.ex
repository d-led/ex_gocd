defmodule ExGoCD.Plugin.OrgHierarchy do
  @moduledoc """
  Provides an organizational tree. Each node has pipeline groups, and access
  propagates down the tree. Used by PipelineGroupPolicy to authorize users.
  """

  @type org_node :: %{
          id: String.t(),
          name: String.t(),
          pipeline_groups: [String.t()],
          children: [org_node()]
        }

  @callback org_tree(keyword()) :: org_node()
  @callback pipeline_groups_for_user(ExGoCD.Accounts.User.t(), keyword()) :: [String.t()]
  @callback user_org_node(ExGoCD.Accounts.User.t(), keyword()) :: {:ok, org_node()} | nil
end
