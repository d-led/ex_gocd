defmodule ExGoCD.Pipelines.Material do
  @moduledoc """
  A material is a trigger for a pipeline (source code repository, dependency, etc.).

  Materials include source code repositories (Git, SVN, etc.), pipeline dependencies,
  package repositories, and timer triggers. GoCD polls materials for changes.

  Based on GoCD source: domain/materials/Material.java (interface) + implementations
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.Pipeline

  @type t :: %__MODULE__{
          id: integer() | nil,
          type: String.t(),
          url: String.t() | nil,
          branch: String.t() | nil,
          username: String.t() | nil,
          destination: String.t() | nil,
          auto_update: boolean(),
          filter_ignore: [String.t()],
          filter_include: [String.t()],
          type_specific_config: map(),
          pipelines: [Pipeline.t()],
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "materials" do
    field :type, :string
    field :url, :string
    field :branch, :string
    field :username, :string
    field :destination, :string
    field :auto_update, :boolean, default: true
    field :filter_ignore, {:array, :string}, default: []
    field :filter_include, {:array, :string}, default: []
    field :type_specific_config, :map, default: %{}

    many_to_many :pipelines, Pipeline, join_through: "pipelines_materials"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a material.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(material, attrs) do
    material
    |> cast(attrs, [
      :type,
      :url,
      :branch,
      :username,
      :destination,
      :auto_update,
      :filter_ignore,
      :filter_include,
      :type_specific_config
    ])
    |> validate_required([:type])
    |> validate_inclusion(:type, [
      "git",
      "svn",
      "hg",
      "p4",
      "tfs",
      "dependency",
      "package",
      "pluggable_scm"
    ])
  end
end
