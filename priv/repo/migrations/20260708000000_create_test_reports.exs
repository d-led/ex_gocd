defmodule ExGoCD.Repo.Migrations.CreateTestReports do
  use Ecto.Migration

  def change do
    create table(:test_reports) do
      add :job_instance_id, references(:job_instances, on_delete: :delete_all), null: false
      add :total_tests, :integer, default: 0, null: false
      add :total_failures, :integer, default: 0, null: false
      add :total_errors, :integer, default: 0, null: false
      add :total_skipped, :integer, default: 0, null: false
      add :total_time, :float, default: 0.0, null: false
      add :passed, :integer, default: 0, null: false
      add :failed, :integer, default: 0, null: false
      add :errored, :integer, default: 0, null: false
      add :skipped, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:test_reports, [:job_instance_id])

    create table(:test_suites) do
      add :test_report_id, references(:test_reports, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :tests, :integer, default: 0, null: false
      add :failures, :integer, default: 0, null: false
      add :errors, :integer, default: 0, null: false
      add :skipped, :integer, default: 0, null: false
      add :time, :float, default: 0.0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:test_suites, [:test_report_id])

    create table(:test_cases) do
      add :test_suite_id, references(:test_suites, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :classname, :string, default: ""
      add :time, :float, default: 0.0, null: false
      add :result, :string, default: "passed", null: false
      add :message, :text
      add :failure_type, :string

      timestamps(type: :utc_datetime)
    end

    create index(:test_cases, [:test_suite_id])
  end
end
