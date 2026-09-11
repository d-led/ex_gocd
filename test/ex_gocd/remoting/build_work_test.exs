defmodule ExGoCD.Remoting.BuildWorkTest do
  use ExUnit.Case, async: true

  alias ExGoCD.AgentJobRuns.AgentJobRun
  alias ExGoCD.Remoting.BuildWork
  alias ExGoCD.RemotingFixture

  @run %AgentJobRun{
    id: 35,
    agent_uuid: "agent-uuid",
    build_id: "build-1",
    pipeline_name: "capture-protocol",
    pipeline_counter: 3,
    stage_name: "probe",
    stage_counter: 1,
    job_name: "probe-job"
  }

  defp payload(sub_commands) do
    %{"buildCommand" => %{"name" => "compose", "subCommands" => sub_commands}}
  end

  defp exec(command, args) do
    %{"name" => "exec", "command" => command, "args" => args, "workingDirectory" => ""}
  end

  describe "wire format" do
    test "matches the shape captured from a real GoCD server" do
      captured = RemotingFixture.json("build_work_response.json")

      rendered =
        BuildWork.render(payload([exec("echo", ["capture-me"])]), @run)

      assert Map.keys(rendered) == Map.keys(captured)
      assert Map.keys(rendered["assignment"]) == Map.keys(captured["assignment"])

      assert Map.keys(rendered["assignment"]["jobIdentifier"]) ==
               Map.keys(captured["assignment"]["jobIdentifier"])
    end

    test "builders carry the same fields as GoCD's CommandBuilderWithArgList" do
      captured = RemotingFixture.json("build_work_response.json")
      [captured_builder] = captured["assignment"]["builders"]

      rendered = BuildWork.render(payload([exec("echo", ["capture-me"])]), @run)
      [builder] = rendered["assignment"]["builders"]

      assert Map.keys(builder) == Map.keys(captured_builder)
      assert Map.keys(builder["cancelBuilder"]) == Map.keys(captured_builder["cancelBuilder"])
      assert builder["type"] == captured_builder["type"]
    end

    test "identifies the build with a numeric id, because the agent parses it as a number" do
      rendered = BuildWork.render(payload([exec("echo", ["hi"])]), @run)

      assert rendered["assignment"]["jobIdentifier"] == %{
               "pipelineName" => "capture-protocol",
               "pipelineCounter" => 3,
               "pipelineLabel" => "3",
               "stageName" => "probe",
               "stageCounter" => "1",
               "buildName" => "probe-job",
               "buildId" => 35
             }
    end
  end

  describe "task translation" do
    test "renders each exec task as a runnable builder, in order" do
      rendered =
        BuildWork.render(
          payload([exec("chmod", ["+x", "gradlew"]), exec("./gradlew", ["--no-daemon"])]),
          @run
        )

      assert Enum.map(rendered["assignment"]["builders"], & &1["command"]) == [
               "chmod",
               "./gradlew"
             ]

      assert Enum.map(rendered["assignment"]["builders"], & &1["args"]) == [
               ["+x", "gradlew"],
               ["--no-daemon"]
             ]
    end

    test "describes the task the way GoCD does" do
      rendered = BuildWork.render(payload([exec("echo", ["capture-me"])]), @run)

      assert [%{"description" => "echo capture-me"}] = rendered["assignment"]["builders"]
    end

    test "turns export subcommands into environment properties instead of builders" do
      export = %{
        "name" => "export",
        "args" => ["MY_VAR", "my-value"],
        "attributes" => %{"secure" => false}
      }

      rendered = BuildWork.render(payload([export, exec("echo", ["hi"])]), @run)

      assert length(rendered["assignment"]["builders"]) == 1

      properties = rendered["assignment"]["initialContext"]["properties"]

      assert %{"name" => "MY_VAR", "value" => "my-value"} =
               Enum.find(properties, &(&1["name"] == "MY_VAR"))
    end

    test "reports secret environment variables as secure" do
      secret = %{
        "name" => "export",
        "args" => ["API_TOKEN", "s3cret"],
        "attributes" => %{"secure" => true}
      }

      rendered = BuildWork.render(payload([secret]), @run)

      assert %{"name" => "API_TOKEN", "secure" => true} =
               Enum.find(
                 rendered["assignment"]["initialContext"]["properties"],
                 &(&1["name"] == "API_TOKEN")
               )
    end

    test "turns artifact uploads into artifact plans rather than builders" do
      upload = %{
        "name" => "uploadArtifact",
        "src" => "build/**/*.jar",
        "dest" => "dist",
        "type" => "build"
      }

      rendered = BuildWork.render(payload([upload, exec("echo", ["hi"])]), @run)

      assert [%{"type" => "BuildArtifactPlan", "src" => "build/**/*.jar", "dest" => "dist"}] =
               rendered["assignment"]["artifactPlans"]

      assert length(rendered["assignment"]["builders"]) == 1
    end
  end

  describe "environment context" do
    test "supplies the GO_* variables GoCD agents expect" do
      rendered = BuildWork.render(payload([exec("echo", ["hi"])]), @run)
      properties = rendered["assignment"]["initialContext"]["properties"]

      values = Map.new(properties, &{&1["name"], &1["value"]})

      assert values["GO_PIPELINE_NAME"] == "capture-protocol"
      assert values["GO_PIPELINE_COUNTER"] == "3"
      assert values["GO_PIPELINE_LABEL"] == "3"
      assert values["GO_STAGE_NAME"] == "probe"
      assert values["GO_STAGE_COUNTER"] == "1"
      assert values["GO_JOB_NAME"] == "probe-job"
    end
  end

  describe "working directory" do
    test "is relative, so it resolves inside the agent's own workspace" do
      rendered = BuildWork.render(payload([exec("echo", ["hi"])]), @run)

      assert rendered["assignment"]["buildWorkingDirectory"]["path"] ==
               "pipelines/capture-protocol/3/probe/1/probe-job"

      assert [%{"workingDir" => %{"path" => path}}] = rendered["assignment"]["builders"]
      assert path == rendered["assignment"]["buildWorkingDirectory"]["path"]
    end
  end

  describe "materials" do
    test "declares that the agent must not fetch materials, because none are sent" do
      rendered = BuildWork.render(payload([exec("echo", ["hi"])]), @run)

      assert rendered["assignment"]["fetchMaterials"] == false
      assert rendered["assignment"]["materialRevisions"] == %{"revisions" => []}
    end
  end
end
