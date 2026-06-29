defmodule ExGoCD.Plugin.Managed.DBAuthProvider do
  @moduledoc """
  Example AuthProvider: authenticates against the local users database.

  Users are stored with Argon2id-hashed passwords (winner of the 2015 Password
  Hashing Competition). Configure via:

      config :ex_gocd, :plugins, auth_provider: ExGoCD.Plugin.Managed.DBAuthProvider
  """

  @behaviour ExGoCD.Plugin.AuthProvider

  alias ExGoCD.Repo
  import Ecto.Query

  @impl true
  def authenticate(%{username: username, password: password}) when is_binary(username) and is_binary(password) do
    case Repo.one(from u in ExGoCD.Accounts.User, where: u.username == ^username) do
      nil ->
        {:error, "Invalid username or password"}

      user ->
        if Argon2.verify_pass(password, user.password_hash || "") do
          if user.status == "Active" do
            {:ok, user}
          else
            {:error, "Account is disabled"}
          end
        else
          {:error, "Invalid username or password"}
        end
    end
  end

  def authenticate(_), do: {:error, "Invalid credentials"}

  @impl true
  def auth_plug_opts do
    [store: :session, key: "username"]
  end
end
