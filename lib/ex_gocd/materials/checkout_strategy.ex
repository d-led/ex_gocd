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

  defmodule SvnCheckout do
    @moduledoc """
    SVN checkout strategy based on GoCD's SvnMaterial.updateTo():
    1. Create destination directory
    2. If working copy exists and URL matches → cleanup, revert, update
    3. If working copy doesn't exist or URL changed → fresh checkout

    The agent-side commands simulate this logic:
    - mkdir -p (dest)
    - svn checkout --non-interactive -r REV URL DEST  (fresh checkout)
    - OR: svn cleanup && svn revert -R . && svn update -r REV  (update existing)

    Since the agent may not have prior state knowledge, we always do a fresh
    checkout (like ForceCheckout for git). The agent receives all auth args.
    """
    @behaviour ExGoCD.Materials.CheckoutStrategy

    @impl true
    def build_checkout_commands(url, _branch, dest, revision) do
      mkdir_cmd =
        if dest != "" do
          [%{"name" => "exec", "command" => "mkdir", "args" => ["-p", dest]}]
        else
          []
        end

      # Always fresh checkout — simplest and most reliable.
      # SVN handles auth via --username/--password passed in args.
      svn_cmds = [
        %{
          "name" => "exec",
          "command" => "svn",
          "args" => ["checkout", "--non-interactive", "-r", revision, url, "."],
          "workingDirectory" => dest
        }
      ]

      mkdir_cmd ++ svn_cmds
    end
  end
end
