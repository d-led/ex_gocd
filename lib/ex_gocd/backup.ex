defmodule ExGoCD.Backup do
  @moduledoc """
  Database backup via pg_dump. Runs asynchronously and reports status.

  The dump is of the database this server is configured with — the same one its
  repository writes to — and lands in `tmp/backups`.
  """

  use GenServer

  @backup_dir "tmp/backups"

  # ── Client API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    ExGoCD.DistSingleton.start_link(__MODULE__, opts)
  end

  @doc "Initiates a backup. Returns :ok if started, {:error, :already_running} if a backup is in progress."
  def create do
    GenServer.call(ExGoCD.DistSingleton.via_horde(__MODULE__), :create)
  end

  @doc "Returns the current backup status: %{status: String.t(), message: String.t()}"
  def status do
    GenServer.call(ExGoCD.DistSingleton.via_horde(__MODULE__), :status)
  end

  @doc """
  Dumps the database `repo_config` names into `filepath`, answering `{:ok,
  output}` or `{:error, reason}`.

  A backup that cannot be taken is an answer, not a crash: anything else would
  leave the status saying "Running" for ever, which is worse than saying what
  went wrong.
  """
  @spec dump_to(String.t(), keyword() | map()) :: {:ok, String.t()} | {:error, String.t()}
  def dump_to(filepath, repo_config \\ ExGoCD.Repo.config()) do
    with {:ok, pg_dump} <- pg_dump_executable() do
      {args, env} = dump_command(Map.new(repo_config), filepath)

      case System.cmd(pg_dump, args, env: env, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, String.trim(output)}
      end
    end
  end

  # ── Server Callbacks ───────────────────────────────────────────────

  @impl true
  def init(_opts) do
    File.mkdir_p!(@backup_dir)
    {:ok, %{status: "Idle", message: "", backup: nil}}
  end

  @impl true
  def handle_call(:create, _from, %{status: "Running"} = state) do
    {:reply, {:error, :already_running}, state}
  end

  def handle_call(:create, _from, _state) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
    filepath = Path.join(@backup_dir, "ex_gocd_backup_#{timestamp}.sql")
    parent = self()

    {_pid, monitor} =
      spawn_monitor(fn -> send(parent, {:backup_complete, dump_to(filepath), filepath}) end)

    {:reply, :ok,
     %{
       status: "Running",
       message: "Backup started at #{DateTime.utc_now() |> DateTime.to_string()}...",
       backup: monitor
     }}
  end

  def handle_call(:status, _from, state) do
    {:reply, %{status: state.status, message: state.message}, state}
  end

  @impl true
  def handle_info({:backup_complete, result, filepath}, %{backup: monitor} = state) do
    Process.demonitor(monitor, [:flush])

    {:noreply, with_result(%{state | backup: nil}, result, filepath)}
  end

  # The dump answers with an error for everything it can foresee; this is for
  # what it cannot, so a crash is reported rather than becoming a stuck status.
  def handle_info({:DOWN, monitor, :process, _pid, reason}, %{backup: monitor} = state) do
    {:noreply,
     %{state | backup: nil, status: "Failed", message: "Backup failed: #{inspect(reason)}"}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ── Private ────────────────────────────────────────────────────────

  defp with_result(state, {:ok, _output}, filepath) do
    case File.stat(filepath) do
      {:ok, %{size: size}} ->
        %{
          state
          | status: "Completed",
            message: "Backup saved to #{filepath} (#{Float.round(size / 1_048_576, 2)} MB)"
        }

      {:error, reason} ->
        %{
          state
          | status: "Failed",
            message:
              "Backup failed: pg_dump answered, but #{filepath} is not there (#{:file.format_error(reason)})"
        }
    end
  end

  defp with_result(state, {:error, reason}, _filepath) do
    %{state | status: "Failed", message: "Backup failed: #{reason}"}
  end

  defp pg_dump_executable do
    name = Application.get_env(:ex_gocd, :pg_dump, "pg_dump")

    case System.find_executable(name) do
      nil -> {:error, "pg_dump (#{name}) is not installed on this server"}
      path -> {:ok, path}
    end
  end

  # However this server was configured — a URL, or the pieces — pg_dump is told
  # about the database the repository itself connects to.
  defp dump_command(%{url: url}, filepath) when is_binary(url) do
    {["--no-owner", "--no-acl", "-f", filepath, "-d", url], []}
  end

  defp dump_command(repo_config, filepath) do
    connection = [
      {"-d", repo_config[:database]},
      {"-h", repo_config[:hostname] || repo_config[:socket_dir]},
      {"-p", repo_config[:port]},
      {"-U", repo_config[:username]}
    ]

    args =
      connection
      |> Enum.reject(fn {_flag, value} -> is_nil(value) end)
      |> Enum.flat_map(fn {flag, value} -> [flag, to_string(value)] end)

    {["--no-owner", "--no-acl", "-f", filepath] ++ args, password_env(repo_config)}
  end

  defp password_env(%{password: password}) when is_binary(password) and password != "",
    do: [{"PGPASSWORD", password}]

  defp password_env(_repo_config), do: []
end
