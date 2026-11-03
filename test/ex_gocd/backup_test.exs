defmodule ExGoCD.BackupTest do
  # `pg_dump` is named by the application environment here, so a test sees what
  # the server would ask it for without taking a real dump.
  use ExUnit.Case, async: false

  alias ExGoCD.{Backup, TestEnv}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    %{calls: Path.join(tmp_dir, "calls"), backup: Path.join(tmp_dir, "backup.sql")}
  end

  describe "taking a dump" do
    test "asks pg_dump for the database this server is configured with", %{
      tmp_dir: tmp_dir,
      calls: calls,
      backup: filepath
    } do
      stub_pg_dump(tmp_dir, calls)

      assert {:ok, _output} =
               Backup.dump_to(filepath, %{
                 database: "ex_gocd_test",
                 hostname: "127.0.0.1",
                 port: 5544,
                 username: "postgres",
                 password: "secret"
               })

      assert recorded(calls) == [
               "--no-owner",
               "--no-acl",
               "-f",
               filepath,
               "-d",
               "ex_gocd_test",
               "-h",
               "127.0.0.1",
               "-p",
               "5544",
               "-U",
               "postgres",
               "password=secret"
             ]
    end

    test "a database named as a URL is handed to pg_dump as one", %{
      tmp_dir: tmp_dir,
      calls: calls,
      backup: filepath
    } do
      stub_pg_dump(tmp_dir, calls)

      assert {:ok, _output} =
               Backup.dump_to(filepath, url: "ecto://postgres:secret@db:5433/ex_gocd")

      assert recorded(calls) == [
               "--no-owner",
               "--no-acl",
               "-f",
               filepath,
               "-d",
               "ecto://postgres:secret@db:5433/ex_gocd"
             ]
    end

    test "a dump that failed says what pg_dump said", %{tmp_dir: tmp_dir, backup: filepath} do
      stub_pg_dump(tmp_dir, Path.join(tmp_dir, "calls"), "echo 'connection refused' >&2\nexit 1")

      assert {:error, reason} = Backup.dump_to(filepath, [])
      assert reason =~ "connection refused"
    end

    test "a server without pg_dump says so instead of failing silently", %{backup: filepath} do
      TestEnv.replace(:pg_dump, "pg_dump-not-installed-here")

      assert {:error, reason} = Backup.dump_to(filepath, database: "ex_gocd")
      assert reason =~ "pg_dump (pg_dump-not-installed-here) is not installed"
    end
  end

  # A stand-in for pg_dump: it records how it was called, then runs `body`,
  # which decides whether the dump looks like it worked.
  defp stub_pg_dump(tmp_dir, calls, body \\ "true") do
    path = Path.join(tmp_dir, "pg_dump")

    File.write!(path, """
    #!/bin/sh
    printf '%s\\n' "$@" > "#{calls}"
    if [ -n "$PGPASSWORD" ]; then printf 'password=%s\\n' "$PGPASSWORD" >> "#{calls}"; fi
    #{body}
    """)

    File.chmod!(path, 0o755)
    TestEnv.replace(:pg_dump, path)
  end

  defp recorded(calls), do: calls |> File.read!() |> String.split("\n", trim: true)
end
