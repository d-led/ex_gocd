defmodule ExGoCD.TestReport.TestSuite do
  @moduledoc """
  A single test suite within a test report (e.g. one JUnit `<testsuite>` element).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.TestReport.{TestCase, TestReport}

  @type t :: %__MODULE__{
          id: integer() | nil,
          test_report_id: integer() | nil,
          name: String.t(),
          tests: integer(),
          failures: integer(),
          errors: integer(),
          skipped: integer(),
          time: float(),
          cases: [TestCase.t()] | Ecto.Association.NotLoaded.t(),
          test_report: TestReport.t() | nil | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "test_suites" do
    field :name, :string
    field :tests, :integer, default: 0
    field :failures, :integer, default: 0
    field :errors, :integer, default: 0
    field :skipped, :integer, default: 0
    field :time, :float, default: 0.0

    belongs_to :test_report, TestReport
    has_many :cases, TestCase, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(suite, attrs) do
    suite
    |> cast(attrs, [:name, :tests, :failures, :errors, :skipped, :time, :test_report_id])
    |> validate_required([:name, :test_report_id])
  end
end
