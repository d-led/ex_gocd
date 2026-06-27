defmodule ExGoCD.SvnTest do
  use ExGoCD.DataCase
  import ExGoCD.Svn

  describe "svn_auth_args/1" do
    test "returns only --non-interactive when no auth provided" do
      assert svn_auth_args([]) == ["--non-interactive"]
    end

    test "includes --username when only username is given" do
      args = svn_auth_args(username: "alice")
      assert "--username" in args
      assert "alice" in args
      assert "--no-auth-cache" in args
      assert "--non-interactive" in args
      refute "--password" in args
    end

    test "includes --username and --password when both are given" do
      args = svn_auth_args(username: "alice", password: "secret")
      assert "--username" in args
      assert "alice" in args
      assert "--password" in args
      assert "secret" in args
      assert "--no-auth-cache" in args
      assert "--non-interactive" in args
    end

    test "does not include password args when password is empty" do
      args = svn_auth_args(username: "alice", password: "")
      assert "--username" in args
      assert "alice" in args
      refute "--password" in args
    end

    test "does not include username args when username is nil or empty" do
      args = svn_auth_args(username: nil)
      assert args == ["--non-interactive"]

      args = svn_auth_args(username: "")
      assert args == ["--non-interactive"]
    end
  end

  describe "parse_info_xml/1" do
    test "parses svn info --xml output" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <info>
      <entry
         kind="dir"
         path="."
         revision="42">
      <url>https://svn.example.com/repo/trunk</url>
      <relative-url>^/trunk</relative-url>
      <repository>
      <root>https://svn.example.com/repo</root>
      <uuid>abc123-def456-789</uuid>
      </repository>
      <wc-info>
      <schedule>normal</schedule>
      <depth>infinity</depth>
      </wc-info>
      <commit
         revision="42">
      <author>jdoe</author>
      <date>2025-01-15T10:30:00.000000Z</date>
      </commit>
      </entry>
      </info>
      """

      result = parse_info_xml(xml)
      assert result.revision == "42"
      assert result.author == "jdoe"
      assert result.date == "2025-01-15T10:30:00.000000Z"
      assert result.url == "https://svn.example.com/repo/trunk"
      assert result.root == "https://svn.example.com/repo"
      assert result.uuid == "abc123-def456-789"
    end

    test "handles empty/missing fields gracefully" do
      xml = "<info><entry></entry></info>"
      result = parse_info_xml(xml)
      assert result.revision == ""
      assert result.author == ""
    end
  end

  describe "parse_log_xml/1" do
    test "parses svn log --xml output" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <log>
      <logentry
         revision="7">
      <author>jsmith</author>
      <date>2025-06-01T14:22:33.123456Z</date>
      <msg>Fix authentication bug in login flow</msg>
      </logentry>
      </log>
      """

      result = parse_log_xml(xml)
      assert result.revision == "7"
      assert result.author == "jsmith"
      assert result.date == "2025-06-01T14:22:33.123456Z"
      assert result.message == "Fix authentication bug in login flow"
    end

    test "handles multiline commit messages" do
      xml = """
      <?xml version="1.0"?>
      <log>
      <logentry revision="3">
      <author>dev</author>
      <date>2025-01-01T00:00:00.000000Z</date>
      <msg>Line one
      Line two
      Line three</msg>
      </logentry>
      </log>
      """

      result = parse_log_xml(xml)
      assert result.revision == "3"
      assert result.message =~ "Line one"
      assert result.message =~ "Line three"
    end
  end

  describe "info_revision/2" do
    @tag :svn_required
    test "returns revision for a valid URL" do
      # This test requires SVN to be installed and a reachable URL.
      # Skip in CI unless SVN is available.
      if available?() do
        # Use a public SVN repo for testing
        result =
          info_revision("https://svn.apache.org/repos/asf/subversion/trunk",
            timeout: 15_000
          )

        assert {:ok, rev} = result
        assert is_binary(rev)
        {n, _} = Integer.parse(rev)
        assert n > 0
      end
    end
  end

  describe "available?/0" do
    test "returns boolean" do
      assert is_boolean(available?())
    end
  end
end
