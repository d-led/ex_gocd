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
    Robust checkout strategy for Git materials.

    The GoCD agent handles directory lifecycle in platform-safe Go code:
      - Creates the per-job working directory (os.MkdirAll)
      - Nukes stale .git directory (os.RemoveAll) to prevent shallow-clone corruption
      - Runs circular cleanup of old job directories

    This strategy only emits cross-platform git commands — no mkdir, rm, or
    other shell commands that would break on Windows.
    """
    @behaviour ExGoCD.Materials.CheckoutStrategy

    @impl true
    def build_checkout_commands(url, branch, dest, revision) do
      # Agent owns directory creation & .git cleanup (os.MkdirAll / os.RemoveAll).
      # We only emit portable git commands.
      [
        %{"name" => "exec", "command" => "git", "args" => ["init"], "workingDirectory" => dest},
        %{
          "name" => "exec",
          "command" => "git",
          "args" => ["fetch", "--no-tags", url, branch],
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
    end
  end

  defmodule SvnCheckout do
    @moduledoc """
    SVN checkout strategy. The agent handles directory creation in Go
    (os.MkdirAll), so this module emits only the svn checkout command.
    """
    @behaviour ExGoCD.Materials.CheckoutStrategy

    @impl true
    def build_checkout_commands(url, _branch, dest, revision) do
      [
        %{
          "name" => "exec",
          "command" => "svn",
          "args" => ["checkout", "--non-interactive", "-r", revision, url, "."],
          "workingDirectory" => dest
        }
      ]
    end
  end
end
