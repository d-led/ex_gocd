defmodule ExGoCDWeb.API.Admin.SiteURLController do
  @moduledoc """
  GoCD Site URLs Config API (api-siteurls-config-v1).

  The URLs come from the environment this server was started with — `PHX_URL`,
  `SITE_URL`, `PHX_SECURE_URL`, `SECURE_SITE_URL` — and are reported, not stored:
  there is no row to change, so the documented update is not offered. The values
  answer the documented path and the shorter one this server used first.
  """
  use ExGoCDWeb, :controller

  @doc "GET /api/admin/config/server/site_urls"
  def show(conn, _params) do
    json(conn, %{
      _links: %{
        doc: %{href: "https://api.gocd.org/current/#siteurls-config"},
        self: %{href: "/api/admin/config/server/site_urls"}
      },
      site_url: site_url(),
      secure_site_url: secure_site_url()
    })
  end

  defp site_url do
    System.get_env("PHX_URL") || System.get_env("SITE_URL") || default_url()
  end

  defp secure_site_url do
    System.get_env("PHX_SECURE_URL") || System.get_env("SECURE_SITE_URL") || site_url()
  end

  defp default_url do
    port = Application.get_env(:ex_gocd, ExGoCDWeb.Endpoint)[:http][:port] || 4000
    "http://localhost:#{port}"
  end
end
