defmodule ExGoCDWeb.API.Admin.SiteURLController do
  use ExGoCDWeb, :controller

  @doc "GET /api/admin/site_url — returns current site URL configuration"
  def show(conn, _params) do
    json(conn, %{
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
