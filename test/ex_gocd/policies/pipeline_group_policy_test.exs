defmodule ExGoCD.Policies.PipelineGroupPolicyTest do
  use ExGoCD.DataCase

  alias ExGoCD.Accounts
  alias ExGoCD.Policies.PipelineGroupPolicy

  setup do
    {:ok, admin} = Accounts.create_user(%{username: "pgadmin", display_name: "PG Admin"})
    {:ok, operator} = Accounts.create_user(%{username: "pgop", display_name: "PG Op"})
    {:ok, viewer} = Accounts.create_user(%{username: "pgview", display_name: "PG View"})
    {:ok, nobody} = Accounts.create_user(%{username: "pgnone", display_name: "PG None"})

    Accounts.grant_pipeline_group_permission(admin.id, "mygrp", "admin")
    Accounts.grant_pipeline_group_permission(operator.id, "mygrp", "operator")
    Accounts.grant_pipeline_group_permission(viewer.id, "mygrp", "viewer")

    %{admin: admin, operator: operator, viewer: viewer, nobody: nobody}
  end

  describe "operate_pipeline" do
    test "allows group admin", %{admin: u} do
      assert PipelineGroupPolicy.authorize(:operate_pipeline, u, %{pipeline_group: "mygrp"}) ==
               :ok
    end

    test "allows group operator", %{operator: u} do
      assert PipelineGroupPolicy.authorize(:operate_pipeline, u, %{pipeline_group: "mygrp"}) ==
               :ok
    end

    test "denies group viewer", %{viewer: u} do
      assert PipelineGroupPolicy.authorize(:operate_pipeline, u, %{pipeline_group: "mygrp"}) ==
               {:error, :forbidden}
    end

    test "denies user without group permission", %{nobody: u} do
      assert PipelineGroupPolicy.authorize(:operate_pipeline, u, %{pipeline_group: "mygrp"}) ==
               {:error, :forbidden}
    end
  end

  describe "admin_pipeline" do
    test "allows group admin", %{admin: u} do
      assert PipelineGroupPolicy.authorize(:admin_pipeline, u, %{pipeline_group: "mygrp"}) == :ok
    end

    test "denies group operator", %{operator: u} do
      assert PipelineGroupPolicy.authorize(:admin_pipeline, u, %{pipeline_group: "mygrp"}) ==
               {:error, :forbidden}
    end
  end

  describe "view_pipeline" do
    test "allows group viewer", %{viewer: u} do
      assert PipelineGroupPolicy.authorize(:view_pipeline, u, %{pipeline_group: "mygrp"}) == :ok
    end

    test "denies user without group permission", %{nobody: u} do
      assert PipelineGroupPolicy.authorize(:view_pipeline, u, %{pipeline_group: "mygrp"}) ==
               {:error, :forbidden}
    end
  end

  describe "global admin bypass" do
    test "global admin can operate any group" do
      {:ok, ga} =
        Accounts.create_user(%{username: "globaladm2", display_name: "GA2", roles: ["admin"]})

      assert PipelineGroupPolicy.authorize(:operate_pipeline, ga, %{pipeline_group: "anygrp"}) ==
               :ok
    end
  end
end
