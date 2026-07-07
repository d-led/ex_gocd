defmodule ExGoCD.TestReport.TestCase do
  @moduledoc """
  A single test case within a test suite (e.g. one JUnit `<testcase>` element).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.TestReport.TestSuite

  @type t :: %__MODULE__{
          id: integer() | nil,
          test_suite_id: integer() | nil,
          name: String.t(),
          classname: String.t(),
          time: float(),
          result: String.t(),
          message: String.t() | nil,
          failure_type: String.t() | nil,
          test_suite: TestSuite.t() | nil | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "test_cases" do
    field :name, :string
    field :classname, :string, default: ""
    field :time, :float, default: 0.0
    field :result, :string, default: "passed"
    field :message, :string
    field :failure_type, :string

    belongs_to :test_suite, TestSuite

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(test_case, attrs) do
    test_case
    |> cast(attrs, [:name, :classname, :time, :result, :message, :failure_type, :test_suite_id])
    |> validate_required([:name, :result, :test_suite_id])
    |> validate_inclusion(:result, ~w(passed failed error skipped))
  end
end
