defmodule ExGoCD.Accounts.User do
  @moduledoc """
  Represents the current user for authorization.

  Used by ExGoCD policies (see ExGoCD.Policies). When full auth is added, this can be loaded from
  the database; until then it is built from session or defaults (e.g. dev admin).
  """
  defstruct [:id, :username, :roles]

  @type t :: %__MODULE__{
          id: term(),
          username: String.t() | nil,
          roles: [atom()]
        }

  @doc "Returns true if the user has the given role."
  def has_role?(%__MODULE__{roles: roles}, role) when is_atom(role), do: role in roles
  def has_role?(_, _), do: false
end
