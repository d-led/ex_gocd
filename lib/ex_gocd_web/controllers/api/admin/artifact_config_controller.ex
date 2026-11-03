defmodule ExGoCDWeb.API.Admin.ArtifactConfigController do
  @moduledoc """
  GoCD Artifacts Config API (`api-artifacts-config-v1`).

  `GET` reports where artifacts are stored and when they are purged, with the
  `ETag` a `PUT` has to send back as `If-Match`. GoCD refuses a `PUT` that
  carries no `If-Match` at all, and so does this one, so a client cannot
  silently overwrite a setting it never read.

  Until an administrator stores the settings, `ARTIFACTS_DIR`,
  `EX_GOCD_PURGE_START_GB` and `EX_GOCD_PURGE_UPTO_GB` supply them — see
  `ExGoCD.ServerConfig`.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.ServerConfig

  action_fallback ExGoCDWeb.FallbackController

  @doc "GET /api/admin/config/server/artifact_config"
  def show(conn, _params) do
    config = ServerConfig.artifact_config()

    conn
    |> put_resp_header("etag", ~s|"#{etag(config)}"|)
    |> json(view(config))
  end

  @doc "PUT /api/admin/config/server/artifact_config"
  def update(conn, params) do
    if stale?(conn, etag(ServerConfig.artifact_config())) do
      conn
      |> put_status(:precondition_failed)
      |> json(%{
        message:
          "Someone has modified the entity. Please update your copy with the changes and try again."
      })
    else
      with {:ok, _setting} <- ServerConfig.update(purge_settings_shallow(params)) do
        config = ServerConfig.artifact_config()

        conn
        |> put_resp_header("etag", ~s|"#{etag(config)}"|)
        |> json(view(config))
      end
    end
  end

  defp view(config) do
    %{
      _links: %{
        doc: %{href: "https://api.gocd.org/current/#artifacts-config"},
        self: %{href: "/api/admin/config/server/artifact_config"}
      },
      artifacts_dir: config.artifacts_dir,
      purge_settings: %{
        purge_start_disk_space: config.purge_start_disk_space,
        purge_upto_disk_space: config.purge_upto_disk_space
      }
    }
  end

  # The documented body nests the purge settings; the changeset holds them beside
  # the directory they belong to.
  defp purge_settings_shallow(%{"purge_settings" => purge} = params) do
    params
    |> Map.delete("purge_settings")
    |> Map.merge(purge)
  end

  defp purge_settings_shallow(params), do: params

  defp stale?(conn, etag) do
    case List.first(get_req_header(conn, "if-match")) do
      nil -> true
      if_match -> String.replace(if_match, ~r/^"|"$/, "") != etag
    end
  end

  defp etag(config) do
    [config.artifacts_dir, config.purge_start_disk_space, config.purge_upto_disk_space]
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
