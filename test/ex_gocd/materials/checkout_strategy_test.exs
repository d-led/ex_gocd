defmodule ExGoCD.Materials.CheckoutStrategyTest do
  use ExUnit.Case, async: false

  alias ExGoCD.Materials.CheckoutStrategy

  setup do
    Application.delete_env(:ex_gocd, :checkout_strategy)

    on_exit(fn ->
      Application.delete_env(:ex_gocd, :checkout_strategy)
    end)
  end

  test "ForceCheckout builds robust command tree with mkdir, init, clean, fetch, and force checkout" do
    url = "https://github.com/d-led/ex_gocd.git"
    branch = "main"
    dest = "workspace"
    revision = "c0ffee"

    cmds = CheckoutStrategy.build_checkout_commands(url, branch, dest, revision)

    assert length(cmds) == 5

    assert Enum.at(cmds, 0) == %{"name" => "exec", "command" => "mkdir", "args" => ["-p", dest]}

    assert Enum.at(cmds, 1) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["init"],
             "workingDirectory" => dest
           }

    assert Enum.at(cmds, 2) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["clean", "-fdx"],
             "workingDirectory" => dest
           }

    assert Enum.at(cmds, 3) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["fetch", "--depth=1", url, branch],
             "workingDirectory" => dest
           }

    assert Enum.at(cmds, 4) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["checkout", "-f", revision],
             "workingDirectory" => dest
           }
  end

  test "ForceCheckout handles empty dest by omitting mkdir" do
    url = "https://github.com/d-led/ex_gocd.git"
    branch = "main"
    dest = ""
    revision = "c0ffee"

    cmds = CheckoutStrategy.build_checkout_commands(url, branch, dest, revision)

    assert length(cmds) == 4

    assert Enum.at(cmds, 0) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["init"],
             "workingDirectory" => dest
           }

    assert Enum.at(cmds, 1) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["clean", "-fdx"],
             "workingDirectory" => dest
           }

    assert Enum.at(cmds, 2) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["fetch", "--depth=1", url, branch],
             "workingDirectory" => dest
           }

    assert Enum.at(cmds, 3) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["checkout", "-f", revision],
             "workingDirectory" => dest
           }
  end

  defmodule MockStrategy do
    @behaviour ExGoCD.Materials.CheckoutStrategy
    @impl true
    def build_checkout_commands(_url, _branch, _dest, _revision) do
      [%{"name" => "exec", "command" => "echo", "args" => ["mocked"]}]
    end
  end

  test "uses configured custom strategy from application config" do
    Application.put_env(:ex_gocd, :checkout_strategy, MockStrategy)

    cmds = CheckoutStrategy.build_checkout_commands("url", "branch", "dest", "rev")
    assert cmds == [%{"name" => "exec", "command" => "echo", "args" => ["mocked"]}]
  end
end
