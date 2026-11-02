defmodule ExGoCD.Mcp.Tools.DeliveryTest do
  @moduledoc """
  The review a person would give a pipeline before it is trusted: build once, fast
  feedback, parallel feedback, as code, clean environment.
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

      assert text =~ "1 finding(s): 1 build once."
      assert text =~ "Build once (1):"
      assert text =~ "can rebuild what `build` already built"

      assert [%{"principle" => "build_once", "code" => "rebuilds_upstream"}] =
               Enum.filter(structured["findings"], &(&1["code"] == "rebuilds_upstream"))
    end

    test "that follows the principles has nothing to report" do
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
    test "is reviewed when nothing is given, and a hand-made pipeline is not code" do
      insert_pipeline_with_jobs("hand-made", 1)

      assert {:ok, %{text: text, structured: structured}} =
               Tools.call("gocd_review_delivery", %{}, @reader)

      assert text =~ "As code"
      assert text =~ "`hand-made` is not in a config repository"
      assert Enum.any?(structured["findings"], &(&1["code"] == "not_in_config_repo"))
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
