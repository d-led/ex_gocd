defmodule ExGoCDWeb.API.Admin.SystemAdminsController do
  @moduledoc """
  System administrators. GoCD parity: GET /go/api/admin/security/system_admins.

  ex_gocd has no separate "role with admin privilege" indirection — the `admin`
  role is the privilege — so `roles` is empty and `users` lists everyone with
  that role.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Accounts

  def index(conn, _params) do
    json(conn, %{
      "roles" => [],
      "users" => Accounts.list_admin_users()
    })
  end
end
