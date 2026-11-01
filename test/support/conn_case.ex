defmodule ExGoCDWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ExGoCDWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint ExGoCDWeb.Endpoint

      use ExGoCDWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import ExGoCDWeb.ConnCase

      # This case checks out a sandbox connection, so it cannot run without a database.
      @moduletag :database
    end
  end

  setup tags do
    owner = ExGoCD.DataCase.setup_sandbox(tags)
    ExGoCD.Sandbox.allow_background_processes(owner)

    if Process.whereis(ExGoCD.Scheduler) do
      ExGoCD.Scheduler.clear_queue()
    end

    on_exit(fn ->
      # An async test cannot lend its connection to the shared Scheduler, so it
      # must not drive it either; waiting on its queue is only meaningful when
      # the test ran synchronously.
      unless tags[:async], do: ExGoCD.DataCase.wait_for_scheduler_queue()
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Puts the given username in the Plug session so LiveView's on_mount hook
  recognises the user as authenticated. Use this in tests that require
  admin access to the admin panel.
  """
  def log_in_as(conn, username) do
    Plug.Test.init_test_session(conn, %{"username" => username})
  end
end
