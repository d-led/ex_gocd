defmodule ExGoCDWeb.API.Admin.SiteURLController do
  @moduledoc """
  GoCD Site URLs Config API (`api-siteurls-config-v1`).

  The URLs are stored here, and until one is stored the environment the server
  was started with supplies it — `PHX_URL`/`SITE_URL` and
  `PHX_SECURE_URL`/`SECURE_SITE_URL`; see `ExGoCD.ServerConfig`. A blank URL
  hands that setting back to the environment. `GET /api/admin/site_url` is this
  server's own, shorter spelling of the same read.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.ServerConfig

  action_fallback ExGoCDWeb.FallbackController

  @doc "GET /api/admin/config/server/site_urls"
  def show(conn, _params) do
    json(conn, view(ServerConfig.site_urls()))
  end

  @doc "POST and PUT /api/admin/config/server/site_urls"
  def upsert(conn, params) do
    with {:ok, _setting} <- ServerConfig.update(params) do
      json(conn, view(ServerConfig.site_urls()))
    end
  end

  defp view(urls) do
    %{
      _links: %{
        doc: %{href: "https://api.gocd.org/current/#siteurls-config"},
        self: %{href: "/api/admin/config/server/site_urls"}
      },
      site_url: urls.site_url,
      secure_site_url: urls.secure_site_url
    }
  end
end
