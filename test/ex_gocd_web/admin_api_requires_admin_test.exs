defmodule ExGoCDWeb.AdminApiRequiresAdminTest do
  @moduledoc """
  Everything under `/api/admin` is the admin API: `AdminApiPlug` answers 403 to a
  caller who is not an admin. The role config API was routed through the browser
  pipeline instead and answered 201 to a viewer, so this asks every admin route
  with a viewer's session and holds each one to a refusal.

  One route refuses with 401: `POST /admin/materials/git/notify` asks the
  question itself in `WebhookController.admin_notify/2` and names the missing
  credential a missing credential. What the sweep holds every route to is that the
  caller is refused, so both answers count.
  """
  use ExGoCDWeb.ConnCase, async: true

  import Phoenix.ConnTest

  alias ExGoCD.Accounts

  setup do
    # GoCD open mode: with no admin configured, every caller is an admin. The
    # question here is what happens once one exists.
    {:ok, _admin} =
      Accounts.create_user(%{
        username: "route-admin-#{System.unique_integer([:positive])}",
        display_name: "Admin",
        roles: ["admin"],
        status: "Active"
      })

    {:ok, viewer} =
      Accounts.create_user(%{
        username: "route-viewer-#{System.unique_integer([:positive])}",
        display_name: "Viewer",
        roles: ["viewer"],
        status: "Active"
      })

    %{viewer: viewer.username}
  end

  test "a viewer is refused by every admin route", %{viewer: username} do
    offenders =
      for {verb, path} <- admin_routes(),
          answer = call(username, verb, path),
          answer not in [401, 403],
          do: "#{verb |> to_string() |> String.upcase()} #{path} → #{answer}"

    assert offenders == []
  end

  defp call(username, verb, path) do
    build_conn()
    |> Plug.Test.init_test_session(%{"username" => username})
    |> dispatch(ExGoCDWeb.Endpoint, verb, concretise(path), %{})
    |> Map.fetch!(:status)
  end

  defp concretise(path), do: Regex.replace(~r/:(\w+)/, path, "x")

  defp admin_routes do
    for route <- ExGoCDWeb.Router.__routes__(),
        String.starts_with?(route.path, "/api/admin"),
        do: {route.verb, route.path}
  end
end
