# Copyright 2026 ex_gocd
# ConfigRepo schema — a Git repository that holds pipeline-as-code definitions.

defmodule ExGoCD.ConfigRepos.ConfigRepo do
  @moduledoc """
  A configuration repository that contains pipeline definitions in YAML/JSON format.
  The server periodically pulls these repos and upserts pipeline configs into the database.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          url: String.t() | nil,
          branch: String.t() | nil,
          material_type: String.t() | nil,
          source_type: String.t() | nil,
          plugin_id: String.t() | nil,
          configuration: map() | nil,
          last_parsed_at: DateTime.t() | nil,
          error_message: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "config_repos" do
    field :url, :string
    field :branch, :string, default: "main"
    field :material_type, :string, default: "git"
    field :source_type, :string, default: "gocd_pipeline"
    field :plugin_id, :string
    field :configuration, :map, default: %{}
    field :last_parsed_at, :utc_datetime
    field :error_message, :string

    timestamps(type: :utc_datetime)
  end

  @valid_source_types ["gocd_pipeline", "github_actions", "gitlab_ci"]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(config_repo, attrs) do
    config_repo
    |> cast(attrs, [:url, :branch, :material_type, :source_type, :plugin_id, :configuration, :last_parsed_at, :error_message])
    |> validate_required([:url])
    |> validate_format(:url, ~r{^https?://|^git@}, message: "must be a valid git URL")
    |> validate_inclusion(:material_type, ["git"])
    |> validate_inclusion(:source_type, @valid_source_types)
    |> unique_constraint(:url)
  end
end
