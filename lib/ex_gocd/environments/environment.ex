defmodule ExGoCD.Environments.Environment do
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.Pipeline

  @moduledoc """
  An environment groups pipelines and agents and provides environment variables.
  Environment variables are stored as a map of name -> value strings,
  consistent with how pipeline/stage/job env vars are stored.
  """

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          environment_variables: map() | nil,
          pipelines: [Pipeline.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "environments" do
    field :name, :string
    field :environment_variables, :map, default: %{}

    many_to_many :pipelines, Pipeline,
      join_through: "environment_pipelines",
      on_replace: :delete,
      on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  def changeset(environment, attrs) do
    environment
    |> cast(attrs, [:name, :environment_variables])
    |> validate_required([:name])
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\-\.]+$/,
      message: "must contain only alphanumeric characters, hyphens, underscores, and periods"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:name)
    |> validate_environment_variables()
  end

  defp validate_environment_variables(changeset) do
    validate_change(changeset, :environment_variables, fn :environment_variables, vars ->
      if is_map(vars) do
        []
      else
        [environment_variables: "must be a map of variable name to value strings"]
      end
    end)
  end
end
