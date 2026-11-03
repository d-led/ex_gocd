# Copyright 2026 ex_gocd
# Tests for GoCD Materials API.

defmodule ExGoCDWeb.API.MaterialsControllerTest do
  use ExGoCDWeb.ConnCase, async: true

  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.Material
  alias ExGoCD.Repo

  describe "GET /api/config/materials" do
    test "describes each material by type and fingerprint", %{conn: conn} do
      material = insert_git_material()

      body = conn |> get(~p"/api/config/materials") |> json_response(200)

      assert %{"_embedded" => %{"materials" => materials}} = body
      assert [%{"type" => "git", "fingerprint" => fingerprint}] = materials
      assert fingerprint == Pipelines.material_fingerprint(material)
    end

    test "gives a git material the attributes that tell it apart", %{conn: conn} do
      insert_git_material(branch: "main", destination: "vendor")

      body = conn |> get(~p"/api/config/materials") |> json_response(200)

      assert %{
               "_embedded" => %{
                 "materials" => [
                   %{
                     "attributes" => %{
                       "url" => "https://example.test/widgets.git",
                       "branch" => "main",
                       "destination" => "vendor",
                       "name" => "widgets",
                       "auto_update" => true,
                       "filter" => nil
                     }
                   }
                 ]
               }
             } = body
    end

    test "spells filters out as the rules GoCD uses", %{conn: conn} do
      insert_git_material(filter_ignore: ["**/*.log"], filter_include: ["src/**"])

      body = conn |> get(~p"/api/config/materials") |> json_response(200)

      assert %{"_embedded" => %{"materials" => [%{"attributes" => %{"filter" => rules}}]}} = body

      assert rules == [
               %{"type" => "ignore", "pattern" => "**/*.log"},
               %{"type" => "include", "pattern" => "src/**"}
             ]
    end

    test "a dependency material names the pipeline and stage it watches", %{conn: conn} do
      insert_material(%{
        type: "pipeline",
        url: nil,
        type_specific_config: %{"pipeline_name" => "upstream", "stage_name" => "build"}
      })

      body = conn |> get(~p"/go/api/config/materials") |> json_response(200)

      assert %{
               "_embedded" => %{
                 "materials" => [
                   %{"attributes" => %{"pipeline" => "upstream", "stage" => "build"}}
                 ]
               }
             } = body
    end

    test "carries no password", %{conn: conn} do
      insert_git_material(username: "robot")

      body = conn |> get(~p"/api/config/materials") |> json_response(200)

      assert %{"_embedded" => %{"materials" => [%{"attributes" => attributes}]}} = body
      assert attributes["username"] == "robot"
      refute Map.has_key?(attributes, "password")
      refute Map.has_key?(attributes, "encrypted_password")
    end
  end

  defp insert_git_material(opts \\ []) do
    insert_material(%{
      type: "git",
      url: "https://example.test/widgets.git",
      branch: Keyword.get(opts, :branch, "master"),
      destination: Keyword.get(opts, :destination),
      username: Keyword.get(opts, :username),
      auto_update: true,
      filter_ignore: Keyword.get(opts, :filter_ignore, []),
      filter_include: Keyword.get(opts, :filter_include, []),
      type_specific_config: %{"material_name" => "widgets"}
    })
  end

  defp insert_material(attrs) do
    Repo.insert!(struct(Material, attrs))
  end
end
