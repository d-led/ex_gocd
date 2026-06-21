# Copyright 2026 ex_gocd
# Pipeline Template schema mapping to config templates.

defmodule ExGoCD.Pipelines.Template do
  @moduledoc """
  A template configuration defines a reusable collection of stages and jobs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.Stage

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          stages: [Stage.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "templates" do
    field :name, :string

    has_many :stages, Stage, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a template.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\-\.]+$/,
      message: "must contain only alphanumeric characters, hyphens, underscores, and periods"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:name)
  end
end
