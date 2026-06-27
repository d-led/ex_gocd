defmodule ExGoCD.Materials.CheckoutStrategyTest do
  use ExUnit.Case, async: false

  alias ExGoCD.Materials.CheckoutStrategy

  setup do
    Application.delete_env(:ex_gocd, :checkout_strategy)

    on_exit(fn ->
      Application.delete_env(:ex_gocd, :checkout_strategy)
    end)
  end

  test "ForceCheckout builds robust command tree: mkdir, init, fetch, checkout, clean" do
    url = "https://github.com/d-led/ex_gocd.git"
    branch = "main"
    dest = "workspace"
    revision = "c0ffee"

    cmds = CheckoutStrategy.build_checkout_commands(url, branch, dest, revision)

    assert length(cmds) == 5

    # 1. mkdir -p dest
    assert Enum.at(cmds, 0) == %{"name" => "exec", "command" => "mkdir", "args" => ["-p", dest]}

    # 2. git init (safe on existing repos)
    assert Enum.at(cmds, 1) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["init"],
             "workingDirectory" => dest
           }

    # 3. git fetch --depth=1 --no-tags (shallow, no tag clutter)
    assert Enum.at(cmds, 2) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["fetch", "--depth=1", "--no-tags", url, branch],
             "workingDirectory" => dest
           }

    # 4. git checkout -f revision
    assert Enum.at(cmds, 3) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["checkout", "-f", revision],
             "workingDirectory" => dest
           }

    # 5. git clean -fdx (runs AFTER checkout to clean build artifacts)
    assert Enum.at(cmds, 4) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["clean", "-fdx"],
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

    # 1. git init
    assert Enum.at(cmds, 0) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["init"],
             "workingDirectory" => dest
           }

    # 2. git fetch --depth=1 --no-tags
    assert Enum.at(cmds, 1) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["fetch", "--depth=1", "--no-tags", url, branch],
             "workingDirectory" => dest
           }

    # 3. git checkout -f revision
    assert Enum.at(cmds, 2) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["checkout", "-f", revision],
             "workingDirectory" => dest
           }

    # 4. git clean -fdx (after checkout)
    assert Enum.at(cmds, 3) == %{
             "name" => "exec",
             "command" => "git",
             "args" => ["clean", "-fdx"],
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

  describe "SvnCheckout" do
    test "builds mkdir + svn checkout commands with destination" do
      cmds =
        CheckoutStrategy.SvnCheckout.build_checkout_commands(
          "https://svn.example.com/repo/trunk",
          "trunk",
          "my-pipeline",
          "42"
        )

      assert length(cmds) == 2

      assert %{"command" => "mkdir", "args" => ["-p", "my-pipeline"]} = Enum.at(cmds, 0)

      svn_cmd = Enum.at(cmds, 1)
      assert svn_cmd["command"] == "svn"

      assert svn_cmd["args"] == [
               "checkout",
               "--non-interactive",
               "-r",
               "42",
               "https://svn.example.com/repo/trunk",
               "."
             ]

      assert svn_cmd["workingDirectory"] == "my-pipeline"
    end

    test "skips mkdir when destination is empty" do
      cmds =
        CheckoutStrategy.SvnCheckout.build_checkout_commands(
          "https://svn.example.com/repo",
          "trunk",
          "",
          "1"
        )

      assert length(cmds) == 1
      svn_cmd = Enum.at(cmds, 0)
      assert svn_cmd["command"] == "svn"
      assert svn_cmd["workingDirectory"] == ""
    end
  end
end
