defmodule ExGoCD.Mcp.PromptsTest do
  @moduledoc """
  The workflows: that each one is listed with the arguments it needs, and that
  filling one in produces instructions that name the tools in a workable order.
  """

  use ExUnit.Case, async: true

  alias ExGoCD.Mcp.Prompts

  @ctx %{user: nil, base_url: "http://localhost:4000", remote_ip: "127.0.0.1"}

  test "every prompt says what it is for and what it takes" do
    for prompt <- Prompts.definitions() do
      assert is_binary(prompt["name"])
      assert is_binary(prompt["title"])
      assert is_binary(prompt["description"])

      for argument <- prompt["arguments"] || [] do
        assert is_binary(argument["name"])
        assert is_boolean(argument["required"])
      end
    end
  end

  test "diagnosing a pipeline names that pipeline and reads the console last" do
    assert {:ok, %{"messages" => [%{"role" => "user", "content" => %{"text" => text}}]}} =
             Prompts.get("diagnose_pipeline", %{"pipeline" => "build-app"}, @ctx)

    assert text =~ "build-app"
    assert text =~ "gocd_pipeline_status"
    assert text =~ "gocd_job_console"
  end

  test "diagnosing without a pipeline is refused, and says which argument" do
    assert Prompts.get("diagnose_pipeline", %{}, @ctx) == {:error, "`pipeline` is required."}
  end

  test "why-is-nothing-running separates the three reasons and takes no arguments" do
    assert {:ok, %{"messages" => [%{"content" => %{"text" => text}}]}} =
             Prompts.get("why_is_nothing_running", %{}, @ctx)

    assert text =~ "maintenance"
    assert text =~ "gocd_queue"
    assert text =~ "gocd_list_agents"
  end

  test "a period of health reads as the days it was asked for" do
    assert {:ok, %{"messages" => [%{"content" => %{"text" => text}}]}} =
             Prompts.get("fleet_health", %{"days" => "30"}, @ctx)

    assert text =~ "30 day(s)"
    assert text =~ "days: 30"
  end

  test "an unknown prompt is named as unknown" do
    assert Prompts.get("write_my_release_notes", %{}, @ctx) ==
             {:error,
              "No prompt named `write_my_release_notes`. `prompts/list` says what there is."}
  end
end
