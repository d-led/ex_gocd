defmodule ExGoCDWeb.ChannelCase do
  @moduledoc """
  Test setup for channel tests.

  A channel joins into a process of its own, and the channel handlers reach the
  database (an agent's heartbeat, a job report), so the sandbox connection is
  lent to the whole application for the duration of the test. That rules out
  async: the shared connection cannot serve two tests at once.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest

      alias ExGoCD.Repo

      @endpoint ExGoCDWeb.Endpoint
      @moduletag :database
    end
  end

  setup tags do
    ExGoCD.DataCase.setup_sandbox(tags)
    :ok
  end
end
