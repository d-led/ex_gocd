defmodule ExGoCD.Repo.Migrations.FixStageInstanceDefaults do
  use Ecto.Migration

  def change do
    alter table(:stage_instances) do
      modify :approval_type, :string, default: "success", null: false
      modify :created_time, :utc_datetime, default: fragment("now()"), null: false
    end
  end
end
