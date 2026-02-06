defmodule ExGoCD.Repo.Migrations.AddAgentRuntimeFields do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :working_dir, :string
      add :operating_system, :string
      add :free_space, :bigint
      add :state, :string, default: "Idle"
    end
  end
end
