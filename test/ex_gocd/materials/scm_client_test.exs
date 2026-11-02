defmodule ExGoCD.Materials.ScmClientTest do
  @moduledoc """
  A material's revision poll: the mock the rest of the suite runs against, the
  type dispatch, and the real commands.

  The real commands answer by running a version-control binary, so those tests put
  a stand-in first on the PATH: it records the arguments it was given and prints
  what the test wrote. That is the same contract the binary offers, which is what
  makes the assertions mean something.
  """
  use ExUnit.Case, async: false

  alias ExGoCD.Materials.ScmClient
  alias ExGoCD.Materials.ScmClient.SystemImpl
  alias ExGoCD.Pipelines.Material

  @revision "42"

  setup do
    Application.put_env(:ex_gocd, :scm_client, ScmClient.MockImpl)
    Application.delete_env(:ex_gocd, :mock_scm_revision)
    Application.delete_env(:ex_gocd, :mock_git_revision)

    dir = Path.join(System.tmp_dir!(), "scm-stub-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous_path = System.get_env("PATH")
    System.put_env("PATH", dir <> ":" <> previous_path)

    on_exit(fn ->
      System.put_env("PATH", previous_path)
      File.rm_rf(dir)
      Application.put_env(:ex_gocd, :scm_client, ScmClient.MockImpl)
      Application.delete_env(:ex_gocd, :mock_scm_revision)
      Application.delete_env(:ex_gocd, :mock_git_revision)
    end)

    %{dir: dir}
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
      :ok
    end

    test "returns error for unsupported material types" do
      assert {:error, msg} = ScmClient.latest_revision(build_material("package"))
      assert msg =~ "unsupported"

      assert {:error, msg} = ScmClient.latest_revision(build_material("dependency"))
      assert msg =~ "unsupported"
    end

    test "a git material asks git for the head of its branch", %{dir: dir} do
      stub(dir, "git", """
      echo "$@" >> "#{dir}/calls"
      printf 'f00dbabe\\trefs/heads/main\\n'
      """)

      assert {:ok, details} = ScmClient.latest_revision(build_material("git"))

      assert details.revision == "f00dbabe"
      assert calls(dir) =~ "ls-remote https://example.com/repo.git main"
    end
  end

  describe "svn" do
    setup %{dir: dir} do
      write(dir, "revision", @revision)

      stub(dir, "svn", """
      echo "$@" >> "#{dir}/calls"
      case "$1 $2" in
        "info --show-item") cat "#{dir}/revision" ;;
        "info --xml") cat "#{dir}/info.xml" 2>/dev/null || exit 1 ;;
        "log --xml") cat "#{dir}/log.xml" 2>/dev/null || exit 1 ;;
        *) echo "unexpected: $*" >&2; exit 3 ;;
      esac
      """)

      :ok
    end

    test "reads the revision and who wrote it", %{dir: dir} do
      write(dir, "log.xml", log_xml(author: "Jane Doe", message: "Fix the build"))

      assert {:ok, details} = latest_revision()

      assert details.revision == @revision
      assert details.committer_name == "Jane Doe"
      assert details.committer_email == "Jane.Doe@scm.local"
      assert details.comment == "Fix the build"
      assert DateTime.compare(details.modified_time, ~U[2026-11-02 10:11:12Z]) == :eq
    end

    test "a log entry with no author or message still makes a revision", %{dir: dir} do
      write(dir, "log.xml", log_xml(author: "", message: ""))

      assert {:ok, details} = latest_revision()

      assert details.committer_name == "svn"
      assert details.committer_email == "svn@scm.local"
      assert details.comment == "svn revision #{@revision}"
    end

    test "asks what svn info knows when the log cannot be read", %{dir: dir} do
      write(dir, "info.xml", info_xml(author: "Ada Lovelace"))

      assert {:ok, details} = latest_revision()

      assert details.committer_name == "Ada Lovelace"
      assert details.comment == "svn revision #{@revision}"
    end

    test "a revision svn cannot name is a failed poll, not a crash", %{dir: dir} do
      File.rm(Path.join(dir, "revision"))

      assert latest_revision() == {:error, :svn_command_failed}
    end

    test "a branch that is a URL of its own is what gets asked about", %{dir: dir} do
      write(dir, "log.xml", log_xml(author: "Jane Doe", message: "Fix"))

      {:ok, _details} =
        latest_revision(%Material{
          type: "svn",
          url: "https://svn.example.com/trunk",
          branch: "https://svn.example.com/branches/release"
        })

      assert calls(dir) =~ "https://svn.example.com/branches/release"
      refute calls(dir) =~ "https://svn.example.com/trunk"
    end

    test "a material on trunk is asked about at its own url", %{dir: dir} do
      write(dir, "log.xml", log_xml(author: "Jane Doe", message: "Fix"))

      {:ok, _details} =
        latest_revision(%Material{
          type: "svn",
          url: "https://svn.example.com/trunk",
          branch: "trunk"
        })

      assert calls(dir) =~ "https://svn.example.com/trunk"
    end
  end

  describe "the other types" do
    test "mercurial answers with the revision hg identifies", %{dir: dir} do
      stub(dir, "hg", """
      echo "$@" >> "#{dir}/calls"
      printf '9c3f1e2b7a  tip\\n'
      """)

      assert {:ok, details} =
               latest_revision(%Material{
                 type: "hg",
                 url: "https://hg.example.com/repo",
                 branch: "default"
               })

      assert details.revision == "9c3f1e2b7a"
      assert calls(dir) =~ "identify https://hg.example.com/repo -r default"
    end

    test "a repository hg cannot identify is a failed poll", %{dir: dir} do
      stub(dir, "hg", "exit 1\n")

      assert latest_revision(%Material{type: "hg", url: "u", branch: "default"}) ==
               {:error, :hg_command_failed}
    end

    test "perforce answers with the change number it was told", %{dir: dir} do
      stub(dir, "p4", """
      echo "$@" >> "#{dir}/calls"
      echo "Change 4711 by joe@ws on 2026/11/02 10:11:12"
      """)

      assert {:ok, details} =
               latest_revision(%Material{type: "p4", url: "p4.example.com:1666", branch: "main"})

      assert details.revision == "4711"
      assert calls(dir) =~ "changes -m 1 p4.example.com:1666"
    end

    test "output perforce cannot be read still names a revision", %{dir: dir} do
      stub(dir, "p4", "echo 'no idea'\n")

      assert {:ok, details} =
               latest_revision(%Material{type: "p4", url: "p4.example.com:1666", branch: "main"})

      assert details.revision == "unknown"
    end

    test "a perforce server that answers with a fault is a failed poll", %{dir: dir} do
      stub(dir, "p4", "exit 1\n")

      assert latest_revision(%Material{type: "p4", url: "p4.example.com:1666", branch: "main"}) ==
               {:error, :p4_command_failed}
    end

    test "tfs says plainly that it does not poll" do
      assert latest_revision(%Material{type: "tfs", url: "tfs.example.com", branch: "main"}) ==
               {:error, :tfs_not_implemented}
    end
  end

  defp build_material(type, url \\ "https://example.com/repo.git") do
    struct!(Material, type: type, url: url, branch: "main", id: 1)
  end

  defp latest_revision(material \\ nil) do
    material =
      material || %Material{type: "svn", url: "https://svn.example.com/trunk", branch: "trunk"}

    SystemImpl.latest_revision(material)
  end

  defp write(dir, name, content), do: File.write!(Path.join(dir, name), content)

  defp stub(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, "#!/usr/bin/env bash\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  defp calls(dir), do: File.read!(Path.join(dir, "calls"))

  defp log_xml(author: author, message: message) do
    """
    <?xml version="1.0"?>
    <log>
    <logentry revision="#{@revision}">
    <author>#{author}</author>
    <date>2026-11-02T10:11:12.000000Z</date>
    <msg>#{message}</msg>
    </logentry>
    </log>
    """
  end

  defp info_xml(author: author) do
    """
    <?xml version="1.0"?>
    <info>
    <entry kind="dir" path="trunk" revision="#{@revision}">
    <url>https://svn.example.com/trunk</url>
    <relative-url>^/trunk</relative-url>
    <commit revision="#{@revision}">
    <author>#{author}</author>
    <date>2026-11-02T10:11:12.000000Z</date>
    </commit>
    </entry>
    </info>
    """
  end
end
