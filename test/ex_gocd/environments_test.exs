defmodule ExGoCD.EnvironmentsTest do
  @moduledoc """
  Behavior-driven tests for the Environments context.
  """
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Environments
  alias ExGoCD.Environments.Environment
  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Repo

  defp insert_pipeline(name) do
    Repo.insert!(%Pipeline{
      name: name,
      group: "default",
      label_template: "${COUNT}"
    })
  end

  describe "create_environment/1" do
    test "creates an environment with valid attributes" do
      attrs = %{
        "name" => "production",
        "environment_variables" => [
          %{"name" => "DB_HOST", "value" => "prod-db"},
          %{"name" => "PORT", "value" => "5432"}
        ]
      }

      assert {:ok, %Environment{} = env} = Environments.create_environment(attrs)
      assert env.name == "production"
      assert env.environment_variables == [
               %{"name" => "DB_HOST", "value" => "prod-db"},
               %{"name" => "PORT", "value" => "5432"}
             ]
    end

    test "associates pipelines during creation" do
      p1 = insert_pipeline("pipeline-1")
      p2 = insert_pipeline("pipeline-2")

      attrs = %{
        "name" => "staging",
        "pipelines" => [%{"name" => p1.name}, %{"name" => p2.name}]
      }

      assert {:ok, %Environment{} = env} = Environments.create_environment(attrs)
      assert length(env.pipelines) == 2
      assert Enum.any?(env.pipelines, fn p -> p.id == p1.id end)
      assert Enum.any?(env.pipelines, fn p -> p.id == p2.id end)
    end

    test "fails with invalid name format" do
      invalid_names = ["prod spaces", "prod/slash", "prod@at", ""]

      for name <- invalid_names do
        attrs = %{"name" => name}
        assert {:error, changeset} = Environments.create_environment(attrs)
        assert :name in Map.keys(errors_on(changeset))
      end
    end

    test "fails with duplicate name" do
      attrs = %{"name" => "duplicate-env"}
      assert {:ok, _} = Environments.create_environment(attrs)
      assert {:error, changeset} = Environments.create_environment(attrs)
      assert {:name, {"has already been taken", [constraint: :unique, constraint_name: "environments_name_index"]}} in changeset.errors
    end
  end

  describe "update_environment/2" do
    test "updates name and environment variables" do
      {:ok, env} = Environments.create_environment(%{"name" => "dev-env"})

      attrs = %{
        "name" => "development",
        "environment_variables" => [%{"name" => "KEY", "value" => "VALUE"}]
      }

      assert {:ok, %Environment{} = updated} = Environments.update_environment(env, attrs)
      assert updated.name == "development"
      assert updated.environment_variables == [%{"name" => "KEY", "value" => "VALUE"}]
    end

    test "replaces associated pipelines" do
      p1 = insert_pipeline("pipeline-1")
      p2 = insert_pipeline("pipeline-2")
      {:ok, env} = Environments.create_environment(%{"name" => "test-env", "pipelines" => [%{"name" => p1.name}]})

      assert {:ok, %Environment{} = updated} = Environments.update_environment(env, %{"pipelines" => [%{"name" => p2.name}]})
      assert length(updated.pipelines) == 1
      assert hd(updated.pipelines).id == p2.id
    end
  end

  describe "pipeline environment assignment rules" do
    test "add_pipeline_to_environment/2 binds a pipeline to exactly one environment" do
      p1 = insert_pipeline("pipeline-1")
      {:ok, env_a} = Environments.create_environment(%{"name" => "env-a"})
      {:ok, env_b} = Environments.create_environment(%{"name" => "env-b"})

      # Add to env-a
      assert {:ok, %Environment{} = updated_a} = Environments.add_pipeline_to_environment(env_a.name, p1.name)
      assert hd(updated_a.pipelines).id == p1.id
      assert Environments.get_pipeline_environment(p1.name).id == env_a.id

      # Add to env-b (must automatically remove from env-a)
      assert {:ok, %Environment{} = updated_b} = Environments.add_pipeline_to_environment(env_b.name, p1.name)
      assert hd(updated_b.pipelines).id == p1.id
      assert Environments.get_pipeline_environment(p1.name).id == env_b.id

      # Verify it is no longer in env-a
      refetched_a = Environments.get_environment_by_name(env_a.name)
      assert refetched_a.pipelines == []
    end

    test "remove_pipeline_from_environment/2 unbinds a pipeline" do
      p1 = insert_pipeline("pipeline-1")
      {:ok, env} = Environments.create_environment(%{"name" => "env-c", "pipelines" => [%{"name" => p1.name}]})

      assert {:ok, %Environment{} = updated} = Environments.remove_pipeline_from_environment(env.name, p1.name)
      assert updated.pipelines == []
      assert Environments.get_pipeline_environment(p1.name) == nil
    end
  end

  describe "delete_environment/1" do
    test "deletes the environment record but does not delete pipelines" do
      p1 = insert_pipeline("pipeline-1")
      {:ok, env} = Environments.create_environment(%{"name" => "delete-me", "pipelines" => [%{"name" => p1.name}]})

      assert {:ok, _} = Environments.delete_environment(env)
      assert Environments.get_environment_by_name("delete-me") == nil

      # Pipeline should still exist
      assert Repo.get(Pipeline, p1.id) != nil
    end
  end
end
