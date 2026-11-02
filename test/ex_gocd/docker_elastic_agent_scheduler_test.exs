defmodule ExGoCD.DockerElasticAgentSchedulerTest do
  @moduledoc """
  The Docker elastic scheduler had no test: every decision it makes ends in a
  Docker API call, and the calls are made directly. What can be checked without a
  daemon is checked here — the image a job's resources pick, and the public view of
  a scheduler with nothing running. The tick itself (idle cleanup, scaling,
  maintaining a minimum) still needs the Docker calls behind a seam.

  The scheduler is a cluster singleton, so this runs synchronously.
  """
  use ExGoCD.DataCase, async: false

  alias ExGoCD.DockerElasticAgentScheduler, as: Scheduler
  alias ExGoCD.ElasticAgentProfiles.ElasticAgentProfile

  defp profile(properties) do
    %ElasticAgentProfile{id: Ecto.UUID.generate(), properties: properties}
  end

  describe "pick_image/2" do
    test "takes the image of the first resource the profile maps" do
      profile =
        profile(%{"Image" => "default.png", "ResourceImages" => %{"docker" => "docker.png"}})

      assert Scheduler.pick_image(profile, ["linux", "docker"]) == "docker.png"
    end

    test "falls back to the profile's image when no resource is mapped" do
      profile =
        profile(%{"Image" => "default.png", "ResourceImages" => %{"docker" => "docker.png"}})

      assert Scheduler.pick_image(profile, ["linux"]) == "default.png"
    end

    test "falls back to the profile's image when nothing is mapped at all" do
      profile = profile(%{"Image" => "default.png"})

      assert Scheduler.pick_image(profile, ["docker"]) == "default.png"
    end

    test "a profile with no properties still names an image" do
      assert Scheduler.pick_image(profile(%{}), []) == ElasticAgentProfile.image(profile(%{}))
    end
  end

  describe "a scheduler with nothing running" do
    test "tracks no containers" do
      assert Scheduler.tracked_containers() == %{}
    end

    test "has no events to report" do
      assert Scheduler.recent_events() == []
    end

    test "deleting all containers deletes none" do
      assert Scheduler.delete_all_containers() == 0
    end
  end
end
