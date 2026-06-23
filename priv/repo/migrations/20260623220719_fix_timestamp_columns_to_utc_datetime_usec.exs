defmodule ExGoCD.Repo.Migrations.FixTimestampColumnsToUtcDatetimeUsec do
  use Ecto.Migration

  @doc """
  Fixes timestamp columns that were incorrectly defined as :naive_datetime
  (no timezone, second precision). Changes them to :utc_datetime_usec
  (microsecond precision, treated as UTC by Ecto).

  Affected tables:
  - job_instances: scheduled_at, assigned_at, completed_at
  - stage_instances: scheduled_at, completed_at

  PostgreSQL note: both :naive_datetime and :utc_datetime_usec map to
  `timestamp` types in PG. The difference is in Ecto's type handling:
  :utc_datetime_usec → DateTime with microsecond precision and UTC awareness.
  Max PG precision is microseconds (6 fractional digits), not nanoseconds.
  """
  def change do
    # job_instances: scheduled_at, assigned_at, completed_at
    alter table(:job_instances) do
      modify :scheduled_at, :utc_datetime_usec, null: false, from: :naive_datetime
      modify :assigned_at, :utc_datetime_usec, from: :naive_datetime
      modify :completed_at, :utc_datetime_usec, from: :naive_datetime
    end

    # stage_instances: scheduled_at, completed_at
    alter table(:stage_instances) do
      modify :scheduled_at, :utc_datetime_usec, from: :naive_datetime
      modify :completed_at, :utc_datetime_usec, from: :naive_datetime
    end
  end
end
