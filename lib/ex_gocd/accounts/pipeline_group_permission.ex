# Copyright 2026 ex_gocd
# Pipeline group permission schema — maps users to pipeline groups with roles.

defmodule ExGoCD.Accounts.PipelineGroupPermission do
  @moduledoc """
  A permission that grants a user a role (viewer, operator, admin) on a specific pipeline group.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ExGoCD.Accounts.User

  @valid_roles ["viewer", "operator", "admin"]

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          pipeline_group: String.t() | nil,
          role: String.t() | nil,
          user: User.t() | nil | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pipeline_group_permissions" do
    field :pipeline_group, :string
    field :role, :string, default: "viewer"

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(perm, attrs) do
    perm
    |> cast(attrs, [:user_id, :pipeline_group, :role])
    |> validate_required([:user_id, :pipeline_group])
    |> validate_inclusion(:role, @valid_roles)
    |> unique_constraint([:user_id, :pipeline_group])
    |> foreign_key_constraint(:user_id)
  end
end
