defmodule Mix.Tasks.ExGoCd.AutoDetectK3s do
  @moduledoc """
  Auto-detects k3s config from the local docker container and updates
  the "k3s-local" cluster profile.

      mix ex_gocd.auto_detect_k3s
  """
  use Mix.Task

  @shortdoc "Auto-detect and update k3s cluster profile"
  def run(_args) do
    Mix.Task.run("app.start")

    case ExGoCD.ClusterProfiles.auto_detect_k3s() do
      {:ok, profile} ->
        Mix.shell().info("[OK] k3s-local profile updated (id: #{profile.id})")

      {:error, reason} ->
        Mix.shell().error("[FAIL] #{reason}")
        System.halt(1)
    end
  end
end
