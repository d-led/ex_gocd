defmodule ExGoCD.SchedulerAgentSelectorTest do
  @moduledoc """
  The `ExGoCD.Plugin.AgentSelector` behaviour lets a plugin veto an otherwise
  eligible agent. These tests hold the scheduler to the behaviour's own contract:
  the callback is `select_candidates/3`, and `{:reject, reason}` means the job
  waits for another agent.
  """
  use ExGoCD.DataCase, async: false

  import ExUnit.CaptureLog

  alias ExGoCD.Agents
  alias ExGoCD.Plugin.Registry
  alias ExGoCD.Scheduler
  alias ExGoCDWeb.AgentPresence

  @presence_topic "agent"

  defmodule Approves do
    def select_candidates(agents, _spec, _opts), do: {:ok, agents}
  end

  defmodule Vetoes do
    def select_candidates(_agents, _spec, _opts), do: {:reject, "corporate policy"}
  end

  defmodule Crashes do
    def select_candidates(_agents, _spec, _opts), do: raise("policy server down")
  end

  setup do
    install(Approves)
    on_exit(fn -> install(nil) end)

    # The scheduler writes through its own connection, so its marks outlive a
    # test: each test gets an empty queue and an agent nobody has touched.
    Scheduler.clear_queue()
    uuid = Ecto.UUID.generate()

    {:ok, _} =
      Agents.register_agent(%{
        uuid: uuid,
        hostname: "selector-agent-#{System.unique_integer([:positive])}",
        ipaddress: "127.0.0.1"
      })

    %{uuid: uuid}
  end

  test "an approving selector lets the agent take the job", %{uuid: uuid} do
    install(Approves)
    {:ok, _} = Scheduler.schedule_job(job())
    connect(uuid)

    assert Scheduler.try_assign_work(uuid) == :assigned
    assert Scheduler.pending_count() == 0
  end

  test "a vetoing selector leaves the job queued", %{uuid: uuid} do
    install(Vetoes)
    {:ok, _} = Scheduler.schedule_job(job())
    connect(uuid)

    assert Scheduler.try_assign_work(uuid) == :no_work
    assert Scheduler.pending_count() == 1
  end

  test "a selector that crashes does not stop the queue, and the failure is reported", %{
    uuid: uuid
  } do
    install(Crashes)
    {:ok, _} = Scheduler.schedule_job(job())
    connect(uuid)

    log = capture_log(fn -> assert Scheduler.try_assign_work(uuid) == :assigned end)

    assert Scheduler.pending_count() == 0
    assert log =~ "Agent selector failed"
  end

  # Scheduling offers a job to every agent connected at that moment. The agent
  # connects afterwards, so the one assignment attempt is the one the test asked
  # for.
  defp connect(uuid) do
    AgentPresence.track(self(), @presence_topic, uuid, %{})
  end

  # Standing in for a plugin that registered itself. The registry is a shared
  # process, so this is done in its state rather than through `register/4`, which
  # also records a cluster event.
  defp install(nil) do
    :sys.replace_state(Registry, fn state ->
      state
      |> put_in([:slots, :agent_selector], nil)
      |> put_in([:nodes, :agent_selector], nil)
    end)
  end

  defp install(module) do
    :sys.replace_state(Registry, fn state ->
      state
      |> put_in([:slots, :agent_selector], module)
      |> put_in([:nodes, :agent_selector], node())
    end)
  end

  defp job do
    %{"pipeline" => "p", "stage" => "s", "job" => "j", "resources" => [], "environments" => []}
  end
end
