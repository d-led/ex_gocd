defmodule ExGoCD.Backup do
  @moduledoc """
  Database backup via pg_dump. Runs asynchronously and reports status.

  Uses the DATABASE_URL environment variable to determine connection parameters.
  Backups are stored in the configured backup directory.
  """

  use GenServer

  @backup_dir "tmp/backups"

  # ── Client API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Initiates a backup. Returns :ok if started, {:error, :already_running} if a backup is in progress."
  def create do
    GenServer.call(__MODULE__, :create)
  end

  @doc "Returns the current backup status: %{status: String.t(), message: String.t()}"
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # ── Server Callbacks ───────────────────────────────────────────────

  @impl true
  def init(_opts) do
    File.mkdir_p!(@backup_dir)
    {:ok, %{status: "Idle", message: ""}}
  end

  @impl true
  def handle_call(:create, _from, %{status: "Running"} = state) do
    {:reply, {:error, :already_running}, state}
  end

  def handle_call(:create, _from, state) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
    filename = "ex_gocd_backup_#{timestamp}.sql"
    filepath = Path.join(@backup_dir, filename)

    pid = self()

    Task.start(fn ->
      result = run_pg_dump(filepath)
      send(pid, {:backup_complete, result, filepath})
    end)

    {:reply, :ok, %{status: "Running", message: "Backup started at #{DateTime.utc_now() |> DateTime.to_string()}..."}}
  end

  def handle_call(:status, _from, state) do
    {:reply, %{status: state.status, message: state.message}, state}
  end

  @impl true
  def handle_info({:backup_complete, result, filepath}, state) do
    {status, message} =
      case result do
        {:ok, _output} ->
          size = File.stat!(filepath).size
          size_mb = Float.round(size / 1_048_576, 2)
          {"Completed", "Backup saved to #{filepath} (#{size_mb} MB)"}

        {:error, reason} ->
          {"Failed", "Backup failed: #{reason}"}
      end

    {:noreply, %{state | status: status, message: message}}
  end

  # ── Private ────────────────────────────────────────────────────────

  defp run_pg_dump(filepath) do
    db_url = System.get_env("DATABASE_URL", "ecto://postgres:postgres@localhost/ex_gocd_dev")

    case parse_db_url(db_url) do
      {:ok, opts} ->
        cmd = pg_dump_cmd(opts, filepath)
        case System.cmd("pg_dump", cmd, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, _} -> {:error, String.trim(output)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_db_url("ecto://" <> rest) do
    # ecto://user:pass@host/db
    case Regex.run(~r{^([^:]*):?([^@]*)@([^/]+)/(.+)$}, rest) do
      [_, user, pass, host, db] ->
        {:ok, %{user: user, password: pass, host: host, database: db}}

      nil ->
        {:error, "Invalid DATABASE_URL format"}
    end
  end

  defp pg_dump_cmd(%{user: user, password: pass, host: host, database: db}, filepath) do
    args = ["-h", host, "-U", user, "-d", db, "-f", filepath, "--no-owner", "--no-acl"]
    env = [{"PGPASSWORD", pass}]
    {args, env}
  end
end
