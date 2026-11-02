defmodule ExGoCD.Mcp.Tools.ConfigTest do
  @moduledoc """
  The configuration tools: the XML a GoCD administrator would keep, the versions
  this server recorded, the environments, and the materials.
  """

  use ExGoCD.DataCase, async: true

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.ConfigVersion
  alias ExGoCD.Environments
  alias ExGoCD.Mcp.Tools.Config, as: Tools
  alias ExGoCD.Repo

  @ctx %{
    user: %ExGoCD.Accounts.User{username: "admin", roles: ["admin"], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  test "the config XML is this server's own configuration" do
    insert_pipeline("xml-app")

    assert {:ok, %{structured: structured}} = Tools.call("gocd_config_xml", %{}, @ctx)

    assert structured["xml"] =~ "<pipelines"
    assert structured["xml"] =~ "xml-app"
    assert structured["bytes"] == byte_size(structured["xml"])
  end

  test "environments are listed with the pipelines they group" do
    pipeline = insert_pipeline("env-app")
    {:ok, environment} = Environments.create_environment(%{name: "production"})
    {:ok, _} = Environments.add_pipeline_to_environment(environment.name, pipeline.name)

    assert {:ok, %{text: text, structured: structured}} =
             Tools.call("gocd_environments", %{}, @ctx)

    assert [%{"name" => "production", "pipelines" => ["env-app"]}] = structured["environments"]
    assert text =~ "production"
  end

  test "a material is shown with the latest revision it saw" do
    pipeline = insert_pipeline("material-app")

    material =
      Repo.insert!(%ExGoCD.Pipelines.Material{
        type: "git",
        url: "https://example.test/repo.git",
        branch: "main"
      })

    {:ok, _} = ExGoCD.Pipelines.add_material_to_pipeline(pipeline, material)
    insert_modification(material, "abc123")

    assert {:ok, %{structured: structured}} = Tools.call("gocd_materials", %{}, @ctx)

    assert [%{"url" => "https://example.test/repo.git", "latest_revision" => "abc123"}] =
             structured["materials"]
  end

  test "the recorded configuration versions are listed, and one can be read whole" do
    version =
      Repo.insert!(%ConfigVersion{
        config_hash: "hash-1",
        config_json: %{},
        config_xml: "<cruise><pipelines/></cruise>",
        changed_by: "admin",
        change_reason: "a change"
      })

    assert {:ok, %{structured: structured}} = Tools.call("gocd_config_history", %{}, @ctx)
    assert [%{"id" => id}] = structured["versions"]
    assert id == version.id

    assert {:ok, %{text: text, structured: %{"xml" => xml}}} =
             Tools.call("gocd_config_history", %{"version" => version.id}, @ctx)

    assert xml =~ "<cruise>"
    assert text =~ "a change"
  end

  test "templates bring their stages, and say which pipelines use them" do
    insert_pipeline_with_template("templated", "shared", 1)

    assert {:ok, %{structured: structured}} = Tools.call("gocd_templates", %{}, @ctx)

    assert [%{"name" => "shared", "stages" => ["template-stage"], "used_by" => ["templated"]}] =
             structured["templates"]
  end

  test "groups count their pipelines and how many of them are paused" do
    insert_pipeline("one", group: "ci")
    insert_pipeline("two", group: "ci")
    paused = insert_pipeline("three", group: "ops")
    {:ok, _} = ExGoCD.Pipelines.pause_pipeline(paused.name, "ops", "freezing")

    assert {:ok, %{structured: structured}} = Tools.call("gocd_pipeline_groups", %{}, @ctx)

    assert [
             %{"name" => "ci", "pipelines" => ["one", "two"], "paused" => 0},
             %{"name" => "ops", "pipelines" => ["three"], "paused" => 1}
           ] = structured["groups"]
  end
end
