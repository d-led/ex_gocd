defmodule ExGoCD.Pipelines.MaterialTest do
  use ExGoCD.DataCase, async: true

  alias ExGoCD.Pipelines.Material

  describe "changeset/2" do
    test "valid git material" do
      changeset =
        Material.changeset(%Material{}, %{
          type: "git",
          url: "https://github.com/user/repo.git",
          branch: "main"
        })

      assert changeset.valid?
    end

    test "requires type" do
      changeset = Material.changeset(%Material{}, %{})
      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates type inclusion" do
      changeset =
        Material.changeset(%Material{}, %{
          type: "invalid"
        })

      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "valid material types" do
      for type <- ["git", "svn", "hg", "p4", "tfs", "dependency", "package", "plugin"] do
        changeset =
          Material.changeset(%Material{}, %{
            type: type
          })

        refute Map.has_key?(errors_on(changeset), :type),
               "#{type} should be valid"
      end
    end

    test "accepts filter arrays" do
      changeset =
        Material.changeset(%Material{}, %{
          type: "git",
          filter_ignore: ["*.log", "tmp/**"],
          filter_include: ["src/**"]
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :filter_ignore) == ["*.log", "tmp/**"]
      assert Ecto.Changeset.get_change(changeset, :filter_include) == ["src/**"]
    end

    test "sets default auto_update" do
      changeset = Material.changeset(%Material{}, %{type: "git"})
      assert Ecto.Changeset.get_field(changeset, :auto_update) == true
    end
  end
end
