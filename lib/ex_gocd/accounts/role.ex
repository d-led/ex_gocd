defmodule ExGoCD.Accounts.Role do
  @moduledoc """
  First-class role configuration — mirrors GoCD's `RoleConfig`.

  Roles grant pipeline group permissions. Two types:
  - `gocd` — static list of usernames
  - `plugin` — delegated to an authorization plugin (auth_config_id)
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          name: String.t(),
          type: String.t(),
          users: [String.t()],
          auth_config_id: String.t() | nil,
          properties: map(),
          policy: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "roles" do
    field :name, :string
    field :type, :string, default: "gocd"
    field :users, {:array, :string}, default: []
    field :auth_config_id, :string
    field :properties, :map, default: %{}
    field :policy, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name)a
  @optional_fields ~w(type users auth_config_id properties policy)a

  @doc "Changeset for create/update."
  def changeset(role, attrs) do
    role
    |> Ecto.Changeset.cast(attrs, @required_fields ++ @optional_fields)
    |> Ecto.Changeset.validate_required(@required_fields)
    |> Ecto.Changeset.unique_constraint(:name)
    |> validate_users_not_empty_when_gocd()
  end

  defp validate_users_not_empty_when_gocd(changeset) do
    type = Ecto.Changeset.get_field(changeset, :type, "gocd")
    users = Ecto.Changeset.get_field(changeset, :users, [])

    if type == "gocd" and users == [] do
      Ecto.Changeset.add_error(
        changeset,
        :users,
        "must have at least one user for gocd-type roles"
      )
    else
      changeset
    end
  end
end
