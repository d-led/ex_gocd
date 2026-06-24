# Copyright 2026 ex_gocd
# Checkout strategy module for GoCD agents.

defmodule ExGoCD.Materials.CheckoutStrategy do
  @moduledoc """
  Defines the behaviour for building checkout commands for materials.
  This allows implementing different robust checkout strategies.
  """

  @callback build_checkout_commands(
              url :: String.t(),
              branch :: String.t(),
              dest :: String.t(),
              revision :: String.t()
            ) :: [map()]

  @doc """
  Delegates command building to the configured strategy.
  """
  def build_checkout_commands(url, branch, dest, revision) do
    strategy = Application.get_env(:ex_gocd, :checkout_strategy, __MODULE__.ForceCheckout)
    strategy.build_checkout_commands(url, branch, dest, revision)
  end

  defmodule ForceCheckout do
    @moduledoc """
    A robust checkout strategy that uses force checkout and cleaning
    to ensure the workspace is in a clean state and checkout never fails.
    """
    @behaviour ExGoCD.Materials.CheckoutStrategy

    @impl true
    def build_checkout_commands(url, branch, dest, revision) do
      mkdir_cmd =
        if dest != "" do
          [%{"name" => "exec", "command" => "mkdir", "args" => ["-p", dest]}]
        else
          []
        end

      git_cmds = [
        %{"name" => "exec", "command" => "git", "args" => ["init"], "workingDirectory" => dest},
        %{
          "name" => "exec",
          "command" => "git",
          "args" => ["fetch", "--depth=1", "--no-tags", url, branch],
          "workingDirectory" => dest
        },
        %{
          "name" => "exec",
          "command" => "git",
          "args" => ["checkout", "-f", revision],
          "workingDirectory" => dest
        },
        %{
          "name" => "exec",
          "command" => "git",
          "args" => ["clean", "-fdx"],
          "workingDirectory" => dest
        }
      ]

      mkdir_cmd ++ git_cmds
    end
  end
end
