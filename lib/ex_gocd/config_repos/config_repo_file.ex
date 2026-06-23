defmodule ExGoCD.ConfigRepos.ConfigRepoFile do
  @moduledoc """
  Tracks individual workflow/pipeline files discovered in a config repo.

  Each file has a checksum for change detection and a status indicating
  whether it's new, active, modified, or deleted since last sync.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.ConfigRepos.ConfigRepo

  @type t :: %__MODULE__{
          id: integer() | nil,
          config_repo_id: integer() | nil,
          config_repo: ConfigRepo.t() | nil | Ecto.Association.NotLoaded.t(),
          path: String.t() | nil,
          source_type: String.t() | nil,
          checksum: String.t() | nil,
          last_seen_at: DateTime.t() | nil,
          status: String.t() | nil,
          raw_content: String.t() | nil,
          parsed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_source_types ["github_workflow", "gitlab_pipeline", "gitlab_include", "gitlab_template"]
  @valid_statuses ["new", "active", "deleted", "modified"]

  schema "config_repo_files" do
    field :path, :string
    field :source_type, :string
    field :checksum, :string
    field :last_seen_at, :utc_datetime
    field :status, :string, default: "new"
    field :raw_content, :string
    field :parsed_at, :utc_datetime

    belongs_to :config_repo, ConfigRepo

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :config_repo_id,
      :path,
      :source_type,
      :checksum,
      :last_seen_at,
      :status,
      :raw_content,
      :parsed_at
    ])
    |> validate_required([:config_repo_id, :path, :source_type])
    |> validate_inclusion(:source_type, @valid_source_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:config_repo_id)
    |> unique_constraint([:config_repo_id, :path])
  end
end
