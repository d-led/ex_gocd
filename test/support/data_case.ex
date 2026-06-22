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

  @doc """
  Waits for the scheduler GenServer to become idle and release any
  borrowed sandbox connections. Called in `on_exit` to prevent
  "connection disconnected" noise when test sandboxes tear down.

  Two-phase: (1) drain the mailbox, (2) a sync call guarantees any
  in-flight handle_call has completed and released its DB connection.
  """
  def wait_for_scheduler_queue do
    if pid = Process.whereis(ExGoCD.Scheduler) do
      # Phase 1: drain the GenServer mailbox (max ~1s)
      _ = Enum.reduce_while(1..200, :waiting, fn _i, :waiting ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, 0} -> {:halt, :done}
          {:message_queue_len, _} ->
            Process.sleep(5)
            {:cont, :waiting}
          nil -> {:halt, :dead}
        end
      end)
      # Phase 2: sync call ensures any in-flight handle_call completed
      if Process.alive?(pid), do: ExGoCD.Scheduler.pending_count()
    end
    :ok
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

  # ── Shared test helpers ───────────────────────────────────────────────

  @doc """
  Creates a pipeline with a stage, runs it, and sets stage result.
  Returns {pipeline, stage, instance, stage_instance}.
  Used to reduce boilerplate in VSM, stage, and job tests.
  """
  def create_pipeline_with_result(name, stage_result, stage_state \\ "Completed") do
    alias ExGoCD.Pipelines.{Pipeline, Stage, PipelineInstance, StageInstance}
    alias ExGoCD.Repo

    {:ok, p} = Repo.insert(%Pipeline{} |> Pipeline.changeset(%{name: name, group: "default", label_template: "${COUNT}"}))
    {:ok, stage} = Repo.insert(%Stage{} |> Stage.changeset(%{name: "build", pipeline_id: p.id, order_id: 0}))

    completed_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    created_time = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-300, :second)

    {:ok, instance} = Repo.insert(%PipelineInstance{} |> PipelineInstance.changeset(%{
      pipeline_id: p.id, counter: 1, label: "1", natural_order: 1.0,
      build_cause: %{"materialRevisions" => []}
    }))

    {:ok, si} = Repo.insert(%StageInstance{} |> StageInstance.changeset(%{
      stage_id: stage.id, pipeline_instance_id: instance.id,
      name: "build", counter: 1, order_id: 0,
      state: stage_state, result: stage_result,
      approval_type: "success", created_time: created_time, completed_at: completed_at
    }))

    {p, stage, instance, si}
  end
end
