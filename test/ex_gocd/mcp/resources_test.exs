defmodule ExGoCD.Mcp.ResourcesTest do
  @moduledoc """
  The documents the server publishes: what a client can list, and that reading
  one is the tool's own answer rather than a second copy of it.
  """

  use ExGoCD.DataCase, async: true

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Mcp.Resources

  @ctx %{
    user: %ExGoCD.Accounts.User{username: "reader", roles: [], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  test "what it lists is what it can read, apart from the templated one" do
    for resource <- Resources.definitions() do
      assert {:ok, content} = Resources.read(resource["uri"], @ctx)
      assert content["mimeType"] == resource["mimeType"]
      assert content["uri"] == resource["uri"]
    end

    assert [%{"uriTemplate" => "gocd://pipelines/{name}"}] = Resources.templates()
  end

  test "the dashboard resource is the dashboard tool's answer" do
    insert_pipeline("resource-app")

    assert {:ok, %{"mimeType" => "application/json", "text" => text}} =
             Resources.read("gocd://dashboard", @ctx)

    decoded = Jason.decode!(text)
    assert decoded["total"] == 1
    assert [%{"name" => "resource-app"}] = decoded["pipelines"]
  end

  test "a pipeline resource is the pipeline's configuration, read as the reader" do
    insert_pipeline_with_two_stages("documented")

    assert {:ok, %{"text" => text}} = Resources.read("gocd://pipelines/documented", @ctx)

    decoded = Jason.decode!(text)
    assert decoded["name"] == "documented"
    assert [%{"name" => "stage1"}, %{"name" => "stage2"}] = decoded["stages"]
  end

  test "the XML resource is the configuration document itself" do
    insert_pipeline("xml-resource")

    assert {:ok, %{"mimeType" => "application/xml", "text" => xml}} =
             Resources.read("gocd://config.xml", @ctx)

    assert xml =~ "<?xml"
    assert xml =~ "xml-resource"
  end

  test "a URI the server does not publish says so, and where to look" do
    assert {:error, message} = Resources.read("gocd://robots.txt", @ctx)
    assert message =~ "resources/list"
  end

  test "a pipeline resource for a pipeline that does not exist is the tool's refusal" do
    assert Resources.read("gocd://pipelines/ghost", @ctx) ==
             {:error, "Pipeline 'ghost' not found."}
  end
end
