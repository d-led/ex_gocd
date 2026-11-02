defmodule ExGoCD.Mcp.Tools.StagesTest do
  @moduledoc """
  The stage tools that change something: what they refuse, and what they ask to
  be confirmed before they end work.
  """

  use ExGoCD.DataCase, async: false

  import ExGoCD.PipelinesFixtures

  alias ExGoCD.Mcp.Tools.Stages, as: Tools
  alias ExGoCD.Pipelines

  @ctx %{
    user: %ExGoCD.Accounts.User{username: "operator", roles: ["admin"], status: "Active"},
    base_url: "http://localhost:4000",
    remote_ip: "127.0.0.1"
  }

  setup do
    insert_pipeline("stage-app")
    instance = insert_pipeline_instance_by_name("stage-app", 1, DateTime.utc_now())
    stage = insert_stage_instance(instance.id, "build", state: "Building")
    insert_job_instance_unassigned(stage.id, "compile", DateTime.utc_now())
    :ok
  end

  test "cancelling asks for a confirmation and changes nothing without it" do
    assert {:error, message} =
             Tools.call(
               "gocd_cancel_stage",
               %{"pipeline" => "stage-app", "counter" => 1, "stage" => "build"},
               @ctx
             )

    assert message =~ "confirm: true"
    assert Pipelines.get_stage_instance("stage-app", 1, "build", 1).state == "Building"
  end

  test "a confirmed cancellation ends the stage" do
    assert {:ok, %{structured: %{"cancelled" => true}}} =
             Tools.call(
               "gocd_cancel_stage",
               %{
                 "pipeline" => "stage-app",
                 "counter" => 1,
                 "stage" => "build",
                 "confirm" => true
               },
               @ctx
             )

    assert Pipelines.get_stage_instance("stage-app", 1, "build", 1).result == "Cancelled"
  end

  test "approving a stage that is not waiting for a human is refused as such" do
    assert {:error, message} =
             Tools.call(
               "gocd_approve_stage",
               %{"pipeline" => "stage-app", "counter" => 1, "stage" => "build"},
               @ctx
             )

    assert message =~ "not awaiting approval"
  end

  test "a stage that does not exist is named as such" do
    assert {:error, message} =
             Tools.call(
               "gocd_stage",
               %{
                 "pipeline" => "stage-app",
                 "counter" => 1,
                 "stage" => "nope",
                 "stage_counter" => 1
               },
               @ctx
             )

    assert message == "Stage 'nope' #1 of stage-app #1 not found."
  end
end
