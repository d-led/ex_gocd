defmodule ExGoCD.Pipelines.Material do
  @moduledoc """
  A material is a cause for a pipeline to run (trigger).
  
  Materials include source code repositories (Git, SVN, etc.), pipeline dependencies,
  package repositories, and timer triggers. GoCD polls materials for changes.
  
  Based on GoCD concepts: https://docs.gocd.org/current/introduction/concepts_in_go.html#materials
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

    many_to_many :pipelines, Pipeline, join_through: "pipelines_materials"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a material.
  """
  @spec changeset(t(),map()) :: Ecto.Changeset.t()
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
      :filter_include
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
      "plugin"
    ])
  end
end
