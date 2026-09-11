defmodule ExGoCD.Repo.Migrations.AddWorkPayloadToAgentJobRuns do
  use Ecto.Migration

  @moduledoc """
  Store the work payload handed to an agent, so HTTP-remoting agents can pull it.

  Push-based agents (our own websocket transport) receive the payload over a
  topic. The official GoCD Java agent polls `POST /remoting/api/agent/get_work`
  instead, so the server has to remember what was assigned to whom until the
  agent collects it. `claimed_at` makes collection once-only, matching GoCD's
  behaviour of handing a build assignment to exactly one agent.
  """

  def change do
    alter table(:agent_job_runs) do
      add :work_payload, :map
      add :work_claimed_at, :utc_datetime
    end

    create index(:agent_job_runs, [:agent_uuid, :work_claimed_at])
  end
end
