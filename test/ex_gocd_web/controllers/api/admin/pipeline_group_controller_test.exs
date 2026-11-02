defmodule ExGoCDWeb.API.Admin.PipelineGroupControllerTest do
  @moduledoc """
  `resources "/pipeline_groups", ..., except: [:new, :edit]` declares `PUT`, and
  the controller had no `update/2` to answer it, so every rename raised
  `UndefinedFunctionError`.
  """
  use ExGoCDWeb.ConnCase, async: true

  import ExGoCD.PipelinesFixtures, only: [insert_pipeline: 2]

  alias ExGoCD.Accounts
  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Repo

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{
        username: "group-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    %{conn: log_in_as(conn, admin.username)}
  end

  describe "PUT /go/api/admin/pipeline_groups/:name" do
    test "moves every pipeline of the group to the new name", %{conn: conn} do
      insert_pipeline("deploy", group: "shipping")
      insert_pipeline("release", group: "shipping")
      insert_pipeline("build", group: "elsewhere")

      body =
        conn
        |> put("/go/api/admin/pipeline_groups/shipping", %{"group" => %{"name" => "delivery"}})
        |> json_response(200)

      assert body["name"] == "delivery"
      assert Enum.sort(body["pipelines"]) == ["deploy", "release"]

      assert groups() == %{
               "build" => "elsewhere",
               "deploy" => "delivery",
               "release" => "delivery"
             }
    end

    test "a group nobody made is missing", %{conn: conn} do
      conn = put(conn, "/go/api/admin/pipeline_groups/absent", %{"group" => %{"name" => "x"}})

      assert json_response(conn, 404) == %{"error" => "Pipeline group not found"}
    end

    test "a body that names no new name is refused", %{conn: conn} do
      insert_pipeline("deploy", group: "shipping")

      conn = put(conn, "/go/api/admin/pipeline_groups/shipping", %{"group" => %{}})

      assert conn.status == 422
      assert groups() == %{"deploy" => "shipping"}
    end
  end

  defp groups do
    Repo.all(Pipeline) |> Map.new(&{&1.name, &1.group})
  end
end
