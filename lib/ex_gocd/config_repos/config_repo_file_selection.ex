defmodule ExGoCD.ConfigRepos.ConfigRepoFileSelection do
  @moduledoc """
  Persists wizard choices for each config repo file.

  Stores the selected mode (translate/execute/skip), which jobs/stages
  to include, which triggers to wire, and any manual overrides.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.ConfigRepos.ConfigRepoFile

  @type t :: %__MODULE__{
          id: integer() | nil,
          config_repo_file_id: integer() | nil,
          config_repo_file: ConfigRepoFile.t() | nil | Ecto.Association.NotLoaded.t(),
          mode: String.t() | nil,
          selected_jobs: map() | nil,
          selected_triggers: map() | nil,
          overrides: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_modes ["translate", "execute_act", "execute_gitlab", "skip"]

  schema "config_repo_file_selections" do
    field :mode, :string, default: "translate"
    field :selected_jobs, :map
    field :selected_triggers, :map
    field :overrides, :map, default: %{}

    belongs_to :config_repo_file, ConfigRepoFile

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(selection, attrs) do
    selection
    |> cast(attrs, [:config_repo_file_id, :mode, :selected_jobs, :selected_triggers, :overrides])
    |> validate_required([:config_repo_file_id, :mode])
    |> validate_inclusion(:mode, @valid_modes)
    |> foreign_key_constraint(:config_repo_file_id)
    |> unique_constraint(:config_repo_file_id)
  end
end
