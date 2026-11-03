defmodule ExGoCDWeb.API.Admin.BackupControllerTest do
  @moduledoc """
  A backup is started by a POST that carries nothing, so it is one of the calls
  GoCD asks to say it was meant. Only the refusal is tested here: it is the plug
  that answers, before a `pg_dump` is started.
  """
  use ExGoCDWeb.ConnCase, async: true

  import ExGoCDWeb.ConfirmHeader

  describe "POST /api/admin/backups" do
    test "asks an empty request to confirm itself", %{conn: conn} do
      assert_unconfirmed_request_refused(post(conn, "/api/admin/backups"))
    end
  end
end
