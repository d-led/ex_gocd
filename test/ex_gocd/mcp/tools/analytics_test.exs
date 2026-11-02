defmodule ExGoCD.Mcp.Tools.AnalyticsTest do
  @moduledoc """
  Trends rather than snapshots — and the same numbers the analytics pages show,
  because these tools ask the same functions.
  """

  use ExGoCD.DataCase, async: true

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Mcp.Tools.Analytics, as: Tools

  @ctx %{
    user: %ExGoCD.Accounts.User{username: "admin", roles: ["admin"], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  setup do
    insert_pipeline("trend-app")
    instance = insert_pipeline_instance_by_name("trend-app", 1, DateTime.utc_now())

    insert_stage_instance(instance.id, "build",
      state: "Completed",
      result: "Passed",
      completed_at: DateTime.utc_now()
    )

    :ok
  end

  test "one pipeline's period counts its runs and reports a pass rate" do
    assert {:ok, %{structured: structured}} =
             Tools.call(
               "gocd_pipeline_analytics",
               %{"pipeline" => "trend-app", "days" => 7},
               @ctx
             )

    assert structured["run_count"] == 1
    assert structured["pass_rate"] == 100.0
    assert [%{"counter" => 1}] = structured["recent_runs"]
  end

  test "every pipeline's run count and latest status are counted together" do
    assert {:ok, %{structured: structured}} =
             Tools.call("gocd_pipeline_analytics", %{"days" => 7}, @ctx)

    assert [%{"name" => "trend-app", "run_count" => 1}] = structured["pipelines"]
  end

  test "asking for a value stream map requires saying which one" do
    assert {:error, message} = Tools.call("gocd_value_stream_map", %{}, @ctx)
    assert message =~ "pipeline"
  end

  describe "gocd_stage_trends" do
    test "says how the stage has been running, oldest first" do
      assert {:ok, %{structured: structured}} =
               Tools.call(
                 "gocd_stage_trends",
                 %{"pipeline" => "trend-app", "stage" => "build"},
                 @ctx
               )

      assert structured["counts"] == %{"Passed" => 1}
      assert is_integer(structured["median_duration_sec"])
      assert [%{"counter" => 1, "result" => "Passed"}] = structured["trends"]
    end

    test "a pipeline that does not exist is named as such" do
      assert {:error, message} =
               Tools.call("gocd_stage_trends", %{"pipeline" => "ghost", "stage" => "build"}, @ctx)

      assert message == "Pipeline 'ghost' not found."
    end
  end
end
