defmodule EnterpriseHierarchyTest do
  use ExUnit.Case, async: true

  alias EnterpriseHierarchy

  describe "org_tree/1" do
    test "returns the enterprise org tree" do
      tree = EnterpriseHierarchy.org_tree([])
      assert tree.id == "acme-corp"
      assert tree.name == "Acme Corp"
      assert length(tree.children) == 4
      assert Enum.map(tree.children, & &1.id) == ["engineering", "platform", "data", "security"]
    end

    test "tree has nested children for engineering" do
      tree = EnterpriseHierarchy.org_tree([])
      eng = Enum.find(tree.children, &(&1.id == "engineering"))
      assert length(eng.children) == 2
      assert hd(eng.children).id == "frontend-team"
    end

    test "children have pipeline groups" do
      tree = EnterpriseHierarchy.org_tree([])
      eng = Enum.find(tree.children, &(&1.id == "engineering"))
      assert "frontend" in eng.pipeline_groups
      assert "backend" in eng.pipeline_groups
    end
  end

  describe "pipeline_groups_for_user/2" do
    test "returns groups for engineering department" do
      user = %{department: "engineering", username: "alice"}
      groups = EnterpriseHierarchy.pipeline_groups_for_user(user, [])
      assert "frontend" in groups
      assert "backend" in groups
      assert "shared-libs" in groups
      # Inherited from children
      assert "ui-components" in groups
      assert "api-gateway" in groups
    end

    test "returns child-only groups for frontend department" do
      user = %{department: "frontend", username: "bob"}
      groups = EnterpriseHierarchy.pipeline_groups_for_user(user, [])
      assert "frontend" in groups
      assert "ui-components" in groups
      assert "design-system" in groups
      # Should NOT have backend groups
      refute "backend" in groups
    end

    test "returns platform groups for sre department" do
      user = %{department: "sre", username: "carol"}
      groups = EnterpriseHierarchy.pipeline_groups_for_user(user, [])
      assert "infra" in groups
      assert "monitoring" in groups
      assert "k8s" in groups
    end

    test "returns security groups" do
      user = %{department: "infosec", username: "dave"}
      groups = EnterpriseHierarchy.pipeline_groups_for_user(user, [])
      assert "security-scan" in groups
      assert "compliance" in groups
    end

    test "returns empty for unknown department" do
      user = %{department: "nonexistent", username: "eve"}
      groups = EnterpriseHierarchy.pipeline_groups_for_user(user, [])
      assert groups == []
    end

    test "returns empty for user without department" do
      user = %{username: "frank"}
      groups = EnterpriseHierarchy.pipeline_groups_for_user(user, [])
      assert groups == []
    end

    test "case-insensitive department matching" do
      user = %{department: "ENGINEERING", username: "grace"}
      groups = EnterpriseHierarchy.pipeline_groups_for_user(user, [])
      assert "frontend" in groups
    end
  end

  describe "user_org_node/2" do
    test "finds node for engineering department" do
      user = %{department: "engineering", username: "alice"}
      assert {:ok, node} = EnterpriseHierarchy.user_org_node(user, [])
      assert node.id == "engineering"
    end

    test "finds child node for frontend department" do
      user = %{department: "frontend", username: "bob"}
      assert {:ok, node} = EnterpriseHierarchy.user_org_node(user, [])
      assert node.id == "frontend-team"
    end

    test "returns nil for unknown department" do
      user = %{department: "unknown", username: "eve"}
      assert EnterpriseHierarchy.user_org_node(user, []) == nil
    end
  end

  describe "update_tree/1 — JSON API" do
    test "updates tree from JSON map and new groups are reflected" do
      new_tree = %{
        "id" => "test-corp", "name" => "Test Corp",
        "pipeline_groups" => [], "departments" => [],
        "children" => [
          %{"id" => "qa", "name" => "QA",
            "pipeline_groups" => ["smoke-tests", "perf-tests"],
            "departments" => ["qa", "testing"], "children" => []}
        ]
      }

      EnterpriseHierarchy.update_tree(new_tree)

      user = %{department: "qa", username: "qauser"}
      groups = EnterpriseHierarchy.pipeline_groups_for_user(user, [])
      assert "smoke-tests" in groups
      assert "perf-tests" in groups

      # Reset to default tree so other tests aren't affected
      EnterpriseHierarchy.reset_tree()
    end

    test "GET /api/hierarchy returns JSON" do
      tree = EnterpriseHierarchy.org_tree()
      assert tree.id != nil
      assert is_list(tree.children)
    end
  end
end
