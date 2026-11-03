defmodule ExGoCDWeb.AgentRegistrationTest do
  @moduledoc """
  The endpoints an agent calls before it registers: the token, and the
  certificate it would trust for TLS.

  This server does not terminate TLS — a proxy in front of it does — so it has
  no certificate to hand out. Answering 404 is the honest answer, and the Go
  agent asks only when its server URL is `https`.
  """
  use ExGoCDWeb.ConnCase

  @certificate_paths ["/admin/agent/root_certificate", "/go/admin/agent/root_certificate"]

  test "the root certificate is refused, because this server serves no TLS" do
    for path <- @certificate_paths do
      conn = get(build_conn(), path)

      assert conn.status == 404
      assert response(conn, 404) =~ "behind a proxy"
      refute response(conn, 404) =~ "BEGIN CERTIFICATE"
    end
  end
end
