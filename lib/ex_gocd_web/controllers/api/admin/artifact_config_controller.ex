defmodule ExGoCDWeb.API.Admin.ArtifactConfigController do
  @moduledoc """
  Server artifact configuration. GoCD parity:
  GET /go/api/admin/config/server/artifact_config.
  """
  use ExGoCDWeb, :controller

  def show(conn, _params) do
    json(conn, %{
      "artifacts_dir" => System.get_env("ARTIFACTS_DIR", "artifacts"),
      "purge_settings" => %{
        "purge_start_disk_space" => purge_gb("EX_GOCD_PURGE_START_GB", 10.0),
        "purge_upto_disk_space" => purge_gb("EX_GOCD_PURGE_UPTO_GB", 20.0)
      }
    })
  end

  defp purge_gb(env, default) do
    case System.get_env(env) do
      nil ->
        default

      value ->
        case Float.parse(value) do
          {gb, _} -> gb
          :error -> default
        end
    end
  end
end
