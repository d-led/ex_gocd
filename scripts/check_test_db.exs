#!/usr/bin/env elixir
# Checks that the database the tests will use is reachable, and says what to do
# when it is not. Without this the test step fails with a Postgres connection
# error that says nothing about the container being down.
#
# Run with: elixir scripts/check_test_db.exs

defmodule TestDatabaseCheck do
  @default_host "localhost"
  @default_port 5432

  def main do
    {host, port, source} = target()

    case :gen_tcp.connect(String.to_charlist(host), port, [], 2_000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        IO.puts("[PASS] test database reachable at #{host}:#{port} (from #{source})")
        warn_about_default_port(port, source)
        exit({:shutdown, 0})

      {:error, reason} ->
        IO.puts("""
        [FAIL] no test database at #{host}:#{port} (from #{source}): #{:inet.format_error(reason)}

        Start one and run the tests:
          docker run -d --name gocd-rewrite-test-db -p 5544:5432 \\
            -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=ex_gocd_test postgres:18-alpine
          PGHOST=127.0.0.1 PGPORT=5544 mix test.setup
          PGHOST=127.0.0.1 PGPORT=5544 mix test

        A busy port of another project is why this project keeps its own: 5544.
        """)

        exit({:shutdown, 1})
    end
  end

  # The same order config/test.exs uses: DATABASE_URL first, then PGHOST/PGPORT.
  defp target do    case System.get_env("DATABASE_URL") do
      url when is_binary(url) and url != "" ->
        uri = URI.parse(url)

        {uri.host || @default_host, uri.port || @default_port, "DATABASE_URL"}

      _ ->
        {System.get_env("PGHOST") || @default_host, env_port(), "PGHOST/PGPORT"}
    end
  end

  defp env_port do
    case Integer.parse(System.get_env("PGPORT") || "") do
      {port, ""} -> port
      _ -> @default_port
    end
  end

  # 5432 is usually somebody else's PostgreSQL, and `mix test.setup` would create
  # this project's schema in it.
  defp warn_about_default_port(@default_port, source) when source != "DATABASE_URL" do
    IO.puts("""
    [WARN] that is the default port, which usually belongs to another project.
           This project keeps its own instance on 5544:
             PGHOST=127.0.0.1 PGPORT=5544 mix test.setup && PGHOST=127.0.0.1 PGPORT=5544 mix test
    """)
  end

  defp warn_about_default_port(_port, _source), do: :ok
end

TestDatabaseCheck.main()
