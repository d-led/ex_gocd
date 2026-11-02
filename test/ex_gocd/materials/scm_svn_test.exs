defmodule ExGoCD.Materials.ScmClient.SvnTest do
  @moduledoc """
  The SVN side of a material's revision poll. It answers by running `svn`, so the
  tests put a stand-in `svn` first on the PATH: the script records the arguments
  it was given and prints the XML the test wrote. That is the same contract the
  real binary offers, which is what makes the assertions mean something.

  A module of this suite changes the process environment, so it cannot run beside
  others.
  """
  use ExUnit.Case, async: false

  alias ExGoCD.Materials.ScmClient.SystemImpl
  alias ExGoCD.Pipelines.Material

  @revision "42"

  setup do
    dir = Path.join(System.tmp_dir!(), "fake-svn-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    File.write!(Path.join(dir, "svn"), """
    #!/usr/bin/env bash
    echo "$@" >> "#{dir}/calls"
    case "$1 $2" in
      "info --show-item") cat "#{dir}/revision" ;;
      "info --xml") cat "#{dir}/info.xml" 2>/dev/null || exit 1 ;;
      "log --xml") cat "#{dir}/log.xml" 2>/dev/null || exit 1 ;;
      *) echo "unexpected: $*" >&2; exit 3 ;;
    esac
    """)

    File.chmod!(Path.join(dir, "svn"), 0o755)
    File.write!(Path.join(dir, "revision"), @revision)

    previous_path = System.get_env("PATH")
    System.put_env("PATH", dir <> ":" <> previous_path)

    on_exit(fn ->
      System.put_env("PATH", previous_path)
      File.rm_rf(dir)
    end)

    %{dir: dir}
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
    File.rm(Path.join(dir, "log.xml"))

    assert {:ok, details} = latest_revision()

    assert details.committer_name == "Ada Lovelace"
    assert details.comment == "svn revision #{@revision}"
  end

  test "a revision svn cannot name is a failed poll, not a crash", %{dir: dir} do
    File.rm!(Path.join(dir, "revision"))

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

  defp latest_revision(material \\ nil) do
    material =
      material || %Material{type: "svn", url: "https://svn.example.com/trunk", branch: "trunk"}

    SystemImpl.latest_revision(material)
  end

  defp write(dir, name, content), do: File.write!(Path.join(dir, name), content)

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
