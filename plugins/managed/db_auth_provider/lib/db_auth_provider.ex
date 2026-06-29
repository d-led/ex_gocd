defmodule DbAuthProvider do
  @moduledoc "AuthProvider: delegates to ex_gocd Accounts.verify_password/2 via :erpc."
  def authenticate(%{username: u, password: p}) do
    ex_gocd = Node.list() |> Enum.find(&(to_string(&1) =~ ~r/ex_gocd/))

    if ex_gocd do
      :erpc.call(ex_gocd, ExGoCD.Accounts, :verify_password, [u, p], 2000)
    else
      {:error, :no_ex_gocd_node}
    end
  end

  def description, do: "DB Auth — validates against ex_gocd users table"
  def ui_links, do: []
end
