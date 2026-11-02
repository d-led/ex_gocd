defmodule ExGoCD.GitTest do
  @moduledoc """
  A node without git cannot poll its materials. That has to be an answer, not an
  exception: `System.cmd/3` raises `:enoent` for a missing binary, and the crash
  took the caller with it — in the quickstart image, the config repo poller
  crashed in a loop, and the scheduler went down with it.
  """
  use ExUnit.Case, async: false

  alias ExGoCD.Git

  setup do
    path = System.get_env("PATH")

    on_exit(fn -> System.put_env("PATH", path) end)

    :ok
  end

  test "reading a remote without git answers an error" do
    System.put_env("PATH", "/nonexistent")

    assert {:error, reason} = Git.ls_remote("https://example.com/repo.git", "main")
    assert reason =~ "git is not installed"
  end

  test "reading a commit without git answers an error" do
    System.put_env("PATH", "/nonexistent")

    assert {:error, reason} = Git.commit_details("/tmp", "HEAD")
    assert reason =~ "git is not installed"
  end

  test "short revision without git is nothing, not a crash" do
    System.put_env("PATH", "/nonexistent")

    assert Git.rev_parse_short() == nil
  end
end
