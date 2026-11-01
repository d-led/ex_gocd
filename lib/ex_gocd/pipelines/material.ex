defmodule ExGoCD.Pipelines.Material do
  @moduledoc """
  A material is a trigger for a pipeline (source code repository, dependency, etc.).

  Materials include source code repositories (Git, SVN, etc.), pipeline dependencies,
  package repositories, and timer triggers. GoCD polls materials for changes.

  Based on GoCD source: domain/materials/Material.java (interface) + implementations
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Pipelines.{Modification, Pipeline}

  @type t :: %__MODULE__{
          id: integer() | nil,
          type: String.t() | nil,
          url: String.t() | nil,
          branch: String.t() | nil,
          username: String.t() | nil,
          destination: String.t() | nil,
          auto_update: boolean() | nil,
          filter_ignore: [String.t()] | nil,
          filter_include: [String.t()] | nil,
          type_specific_config: map() | nil,
          pipelines: [Pipeline.t()] | Ecto.Association.NotLoaded.t(),
          modifications: [Modification.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
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
    has_many :modifications, Modification, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a material.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(material, attrs) do
    attrs = fold_identity_into_type_specific_config(attrs)

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

  # GoCD names a material with `materialName`, and a dependency material with the
  # pipeline and stage it watches. None of those is a column of its own: they are
  # per-type attributes, so they belong in `type_specific_config`. Keeping them
  # there means a git material cannot carry a stage name, and a dependency
  # material cannot carry a branch.
  defp fold_identity_into_type_specific_config(attrs)
       when is_map(attrs) and not is_struct(attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    identity =
      for key <- ["name", "pipeline_name", "stage_name"],
          value = attrs[key],
          value not in [nil, ""],
          into: %{},
          do: {identity_attribute(key), value}

    attrs
    |> Map.drop(["name", "pipeline_name", "stage_name"])
    |> Map.put("type_specific_config", Map.merge(attrs["type_specific_config"] || %{}, identity))
  end

  defp fold_identity_into_type_specific_config(attrs), do: attrs

  defp identity_attribute("name"), do: "material_name"
  defp identity_attribute(key), do: key
end
