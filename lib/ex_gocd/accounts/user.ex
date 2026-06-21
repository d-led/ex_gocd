defmodule ExGoCD.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          username: String.t(),
          display_name: String.t(),
          roles: [String.t()],
          status: String.t()
        }

  schema "users" do
    field :username, :string
    field :display_name, :string
    field :roles, {:array, :string}, default: []
    field :status, :string, default: "Active"

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :display_name, :roles, :status])
    |> validate_required([:username, :display_name])
    |> validate_inclusion(:status, ["Active", "Disabled"])
    |> unique_constraint(:username)
  end

  @doc "Returns true if the user has the given role."
  def has_role?(%__MODULE__{roles: roles}, role) do
    role_str = to_string(role)
    Enum.any?(roles || [], &(to_string(&1) == role_str))
  end
  def has_role?(_, _), do: false
end
