defmodule ExGoCDWeb.API.Admin.PluginSettingsController do
  @moduledoc """
  Plugin settings. GoCD parity: GET /go/api/admin/plugin_settings/:plugin_id.

  ex_gocd plugins are standalone OTP apps with no server-side settings store, so
  no plugin id has settings. Returns 404, matching GoCD's behaviour for an
  unknown plugin.
  """
  use ExGoCDWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{"message" => "Plugin settings not found"})
  end
end
