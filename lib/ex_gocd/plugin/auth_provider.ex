defmodule ExGoCD.Plugin.AuthProvider do
  @moduledoc """
  Pluggable authentication. Replace stub auth with LDAP, OAuth, GitHub, etc.
  """

  @callback authenticate(map()) :: {:ok, ExGoCD.Accounts.User.t()} | {:error, term()}
  @callback auth_plug_opts() :: keyword()
end
