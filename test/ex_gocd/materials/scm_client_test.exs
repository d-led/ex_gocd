defmodule ExGoCD.Materials.ScmClientTest do
  @moduledoc """
  Tests for Multi-SCM client — mock mode and type dispatch.
  """
  use ExUnit.Case, async: false

  alias ExGoCD.Materials.ScmClient
  alias ExGoCD.Pipelines.Material

  setup do
    # Ensure MockImpl is active
    Application.put_env(:ex_gocd, :scm_client, ScmClient.MockImpl)
    Application.delete_env(:ex_gocd, :mock_scm_revision)
    Application.delete_env(:ex_gocd, :mock_git_revision)

    on_exit(fn ->
      Application.put_env(:ex_gocd, :scm_client, ScmClient.MockImpl)
      Application.delete_env(:ex_gocd, :mock_scm_revision)
      Application.delete_env(:ex_gocd, :mock_git_revision)
    end)
  end

  defp build_material(type, url \\ "https://example.com/repo.git") do
    struct!(Material, type: type, url: url, branch: "main", id: 1)
  end

  describe "MockImpl" do
    test "returns default mock revision for any material type" do
      assert {:ok, result} = ScmClient.latest_revision(build_material("git"))
      assert result.revision == "a1b2c3d4e5f67890123456789012345678901234"
      assert result.committer_name == "Mock Committer"
    end

    test "returns custom SHA when mock_git_revision is set" do
      Application.put_env(:ex_gocd, :mock_git_revision, "c0ffee")
      assert {:ok, result} = ScmClient.latest_revision(build_material("git"))
      assert result.revision == "c0ffee"
      assert result.committer_name == "Mock Committer"
    end

    test "returns custom map when mock_git_revision is {:ok, map}" do
      Application.put_env(
        :ex_gocd,
        :mock_git_revision,
        {:ok, %{revision: "deadbeef", committer_name: "Custom"}}
      )

      assert {:ok, result} = ScmClient.latest_revision(build_material("git"))
      assert result.revision == "deadbeef"
      assert result.committer_name == "Custom"
    end

    test "returns error when mock_git_revision is {:error, reason}" do
      Application.put_env(:ex_gocd, :mock_git_revision, {:error, :network_down})
      assert {:error, :network_down} = ScmClient.latest_revision(build_material("git"))
    end

    test "mock_scm_revision takes precedence over mock_git_revision" do
      Application.put_env(:ex_gocd, :mock_git_revision, "old_sha")
      Application.put_env(:ex_gocd, :mock_scm_revision, "new_sha")
      assert {:ok, result} = ScmClient.latest_revision(build_material("svn"))
      assert result.revision == "new_sha"
    end

    test "works for svn, hg, p4 material types" do
      for type <- ["svn", "hg", "p4"] do
        assert {:ok, result} = ScmClient.latest_revision(build_material(type))
        assert result.revision != ""
      end
    end
  end

  describe "type dispatch through SystemImpl" do
    setup do
      Application.put_env(:ex_gocd, :scm_client, ScmClient.SystemImpl)
      Application.delete_env(:ex_gocd, :mock_git_revision)
      Application.delete_env(:ex_gocd, :mock_scm_revision)

      on_exit(fn ->
        Application.put_env(:ex_gocd, :scm_client, ScmClient.MockImpl)
      end)
    end

    test "returns error for unsupported material types" do
      assert {:error, msg} = ScmClient.latest_revision(build_material("package"))
      assert msg =~ "unsupported"

      assert {:error, msg} = ScmClient.latest_revision(build_material("dependency"))
      assert msg =~ "unsupported"
    end

    test "delegates to Git inner module for git type" do
      # SystemImpl.Git will run real git ls-remote — which fails gracefully
      result = ScmClient.latest_revision(build_material("git"))
      assert result == {:error, :git_command_failed} or match?({:ok, _}, result)
    end
  end
end
