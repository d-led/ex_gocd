defmodule ExGoCD.Mcp.Tools.DeliveryTest do
  @moduledoc """
  The flow review: what passes between pipelines, and whether the fleet can run the
  shape. Not what the jobs do — that is the author's business.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Accounts
  alias ExGoCD.Mcp.Tools.Delivery, as: Tools

  @reader %{
    user: %Accounts.User{username: "reader", roles: [], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  describe "a proposal" do
    test "that would rebuild what its build built is named, under the principle it breaks" do
      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_review_delivery", %{"pipelines" => rebuild_graph()}, @reader)

      assert text =~ "1 finding(s): 1 what passes between pipelines."
      assert text =~ "What passes between pipelines (1):"
      assert text =~ "can rebuild what `build` already built"

      assert [%{"principle" => "build_once", "code" => "rebuilds_upstream"}] =
               Enum.filter(structured["findings"], &(&1["code"] == "rebuilds_upstream"))
    end

    test "that follows the flow has nothing to report" do
      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_review_delivery", %{"pipelines" => good_graph()}, @reader)

      assert text =~ "no findings"
      assert structured["findings"] == []
    end

    test "is refused the same way create would refuse it" do
      assert {:error, message} =
               Tools.call(
                 "gocd_review_delivery",
                 %{"pipelines" => [%{"name" => "empty", "stages" => []}]},
                 @reader
               )

      assert message =~ "`stages` must be a non-empty list"
    end
  end

  describe "the configuration as it stands" do
    test "is reviewed when nothing is given, and a deploy with no environment is named" do
      {pipeline, _stage, _jobs} = insert_pipeline_with_jobs("deploy", 1)
      attach_dependency(pipeline, "build")

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_review_delivery", %{}, @reader)

      assert text =~ "Where it runs"
      assert text =~ "`deploy` deploys but belongs to no environment"
      assert Enum.any?(structured["findings"], &(&1["code"] == "deploy_without_environment"))
    end
  end

  # ── graphs ─────────────────────────────────────────────────────────

  defp good_graph do
    [
      build(),
      %{
        "name" => "deploy",
        "materials" => [%{"type" => "dependency", "pipeline" => "build", "stage" => "build"}],
        "stages" => [
          %{
            "name" => "deploy",
            "clean_working_directory" => true,
            "jobs" => [
              %{
                "name" => "ship",
                "tasks" => [
                  %{
                    "type" => "fetch",
                    "pipeline" => "build",
                    "stage" => "build",
                    "job" => "compile",
                    "src" => "pkg/app.jar",
                    "dest" => "lib"
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  end

  defp rebuild_graph do
    [build, deploy] = good_graph()

    deploy =
      put_in(deploy["materials"], [
        %{"type" => "git", "url" => "https://example.test/app.git"} | deploy["materials"]
      ])

    [build, deploy]
  end

  defp attach_dependency(pipeline, upstream) do
    material =
      ExGoCD.Repo.insert!(
        %ExGoCD.Pipelines.Material{}
        |> ExGoCD.Pipelines.Material.changeset(%{type: "dependency", url: upstream})
      )

    pipeline
    |> ExGoCD.Repo.preload(:materials)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:materials, [material])
    |> ExGoCD.Repo.update!()
  end

  defp build do
    %{
      "name" => "build",
      "materials" => [%{"type" => "git", "url" => "https://example.test/app.git"}],
      "stages" => [
        %{
          "name" => "build",
          "jobs" => [
            %{
              "name" => "compile",
              "artifacts" => [%{"src" => "target/app.jar", "dest" => "pkg"}],
              "tasks" => [%{"command" => "make"}]
            }
          ]
        }
      ]
    }
  end
end
