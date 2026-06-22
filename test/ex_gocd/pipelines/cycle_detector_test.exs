defmodule ExGoCD.Pipelines.CycleDetectorTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.CycleDetector

  import ExGoCD.PipelinesFixtures, only: [insert_pipeline: 1, insert_material: 3]

  describe "check_dependency_cycles/0" do
    test "returns :ok for empty database" do
      assert CycleDetector.check_dependency_cycles() == :ok
    end

    test "returns :ok for simple linear dependencies" do
      _pipe_a = insert_pipeline("pipe-a")
      pipe_b = insert_pipeline("pipe-b")
      pipe_c = insert_pipeline("pipe-c")

      # pipe-b depends on pipe-a
      insert_material(pipe_b, "dependency", "pipe-a")
      # pipe-c depends on pipe-b
      insert_material(pipe_c, "dependency", "pipe-b")

      assert CycleDetector.check_dependency_cycles() == :ok
    end

    test "returns :ok for non-dependency materials" do
      pipe_a = insert_pipeline("pipe-a")
      insert_material(pipe_a, "git", "http://github.com/test/repo")

      assert CycleDetector.check_dependency_cycles() == :ok
    end

    test "detects simple cycle: A -> B -> A" do
      pipe_a = insert_pipeline("pipe-a")
      pipe_b = insert_pipeline("pipe-b")

      # A depends on B
      insert_material(pipe_a, "dependency", "pipe-b")
      # B depends on A
      insert_material(pipe_b, "dependency", "pipe-a")

      assert {:error, {:circular_dependency, path}} = CycleDetector.check_dependency_cycles()
      assert path == ["pipe-a", "pipe-b", "pipe-a"] or path == ["pipe-b", "pipe-a", "pipe-b"]
    end

    test "detects multi-hop cycle: A -> B -> C -> A" do
      pipe_a = insert_pipeline("pipe-a")
      pipe_b = insert_pipeline("pipe-b")
      pipe_c = insert_pipeline("pipe-c")

      # A depends on B
      insert_material(pipe_a, "dependency", "pipe-b")
      # B depends on C
      insert_material(pipe_b, "dependency", "pipe-c")
      # C depends on A
      insert_material(pipe_c, "dependency", "pipe-a")

      assert {:error, {:circular_dependency, path}} = CycleDetector.check_dependency_cycles()
      assert "pipe-a" in path
      assert "pipe-b" in path
      assert "pipe-c" in path
      assert List.first(path) == List.last(path)
    end

    test "detects self-loop: A -> A" do
      pipe_a = insert_pipeline("pipe-a")
      # A depends on A
      insert_material(pipe_a, "dependency", "pipe-a")

      assert {:error, {:circular_dependency, ["pipe-a", "pipe-a"]}} = CycleDetector.check_dependency_cycles()
    end

    test "detects missing pipeline dependency reference" do
      pipe_a = insert_pipeline("pipe-a")
      # A depends on non-existent pipe-b
      insert_material(pipe_a, "dependency", "pipe-b")

      assert {:error, {:missing_pipeline, "pipe-b"}} = CycleDetector.check_dependency_cycles()
    end
  end

  describe "mutation integration" do
    test "create_material_for_pipeline/2 rolls back and returns error on cycle" do
      pipe_a = insert_pipeline("pipe-a")
      pipe_b = insert_pipeline("pipe-b")

      # pipe-a depends on pipe-b
      _ = insert_material(pipe_a, "dependency", "pipe-b")

      # Attempting to make pipe-b depend on pipe-a should fail
      assert {:error, {:circular_dependency, path}} =
               ExGoCD.Pipelines.create_material_for_pipeline(pipe_b, %{
                 type: "dependency",
                 url: "pipe-a"
               })

      assert "pipe-a" in path
      assert "pipe-b" in path
    end

    test "update_material/2 rolls back and returns error on cycle" do
      pipe_a = insert_pipeline("pipe-a")
      pipe_b = insert_pipeline("pipe-b")

      # pipe-a depends on pipe-b
      _ = insert_material(pipe_a, "dependency", "pipe-b")

      # pipe-b depends on some safe git material initially
      mat = insert_material(pipe_b, "git", "http://github.com/some/repo")

      # Updating the material to depend on pipe-a should fail
      assert {:error, {:circular_dependency, path}} =
               ExGoCD.Pipelines.update_material(mat, %{
                 type: "dependency",
                 url: "pipe-a"
               })

      assert "pipe-a" in path
      assert "pipe-b" in path
    end
  end
end
