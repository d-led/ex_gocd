defmodule ExGoCD.TestReport.TestReport do
  @moduledoc """
  DB-backed test report summary for a job instance run.

  A test report aggregates multiple test suites (JUnit, NUnit, XUnit) parsed from
  XML files uploaded as test artifacts to the `testoutput/` directory.
  Survives artifact cleanup — results are persisted in the database.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.JobInstance
  alias ExGoCD.TestReport.TestSuite

  @type t :: %__MODULE__{
          id: integer() | nil,
          job_instance_id: integer() | nil,
          total_tests: integer(),
          total_failures: integer(),
          total_errors: integer(),
          total_skipped: integer(),
          total_time: float(),
          passed: integer(),
          failed: integer(),
          errored: integer(),
          skipped: integer(),
          suites: [TestSuite.t()] | Ecto.Association.NotLoaded.t(),
          job_instance: JobInstance.t() | nil | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "test_reports" do
    field :total_tests, :integer, default: 0
    field :total_failures, :integer, default: 0
    field :total_errors, :integer, default: 0
    field :total_skipped, :integer, default: 0
    field :total_time, :float, default: 0.0
    field :passed, :integer, default: 0
    field :failed, :integer, default: 0
    field :errored, :integer, default: 0
    field :skipped, :integer, default: 0

    belongs_to :job_instance, JobInstance
    has_many :suites, TestSuite, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a test report.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :job_instance_id,
      :total_tests,
      :total_failures,
      :total_errors,
      :total_skipped,
      :total_time,
      :passed,
      :failed,
      :errored,
      :skipped
    ])
    |> validate_required([:job_instance_id])
    |> unique_constraint(:job_instance_id)
  end
end
