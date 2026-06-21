defmodule ExGoCD.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ExGoCD.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias ExGoCD.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import ExGoCD.DataCase
    end
  end

  alias Ecto.Adapters.SQL.Sandbox

  setup tags do
    ExGoCD.DataCase.setup_sandbox(tags)

    for name <- [ExGoCD.Scheduler, ExGoCD.Materials.TimerScheduler] do
      if pid = Process.whereis(name) do
        Ecto.Adapters.SQL.Sandbox.allow(ExGoCD.Repo, self(), pid)
      end
    end

    if Process.whereis(ExGoCD.Scheduler) do
      ExGoCD.Scheduler.clear_queue()
    end

    on_exit(fn ->
      wait_for_scheduler_queue()
    end)

    :ok
  end

  def wait_for_scheduler_queue do
    if pid = Process.whereis(ExGoCD.Scheduler) do
      case Process.info(pid, :message_queue_len) do
        {:message_queue_len, 0} -> :ok
        {:message_queue_len, _} ->
          Process.sleep(5)
          wait_for_scheduler_queue()
        nil -> :ok
      end
    else
      :ok
    end
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(ExGoCD.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
