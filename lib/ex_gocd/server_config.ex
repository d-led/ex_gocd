defmodule ExGoCD.ServerConfig do
  @moduledoc """
  This server's own settings — GoCD's `<server>` section: the site URLs its
  links should use, the default job timeout, and where artifacts live.

  A setting is stored when an administrator writes it through the admin API.
  Until then the environment supplies it, so a container that only sets an
  environment variable behaves as it always did, and a stored value wins over
  that variable. A blank site URL hands the setting back to the environment.

  | Setting | Environment it falls back to |
  | --- | --- |
  | site URL | `PHX_URL`, `SITE_URL` |
  | secure site URL | `PHX_SECURE_URL`, `SECURE_SITE_URL` |
  | default job timeout | `DEFAULT_JOB_TIMEOUT` |
  | artifacts directory | `ARTIFACTS_DIR` |
  | purge trigger and goal | `EX_GOCD_PURGE_START_GB`, `EX_GOCD_PURGE_UPTO_GB` |
  """
  import Ecto.Changeset, only: [put_change: 3]

  alias ExGoCD.Repo
  alias ExGoCD.ServerConfig.Setting

  # The table holds this one row, and the migration's check constraint says so.
  @one_row 1

  @doc """
  The URLs a link the server sends out should use: the stored ones, else the
  environment's, else the address this server answers on.
  """
  def site_urls do
    stored = stored()
    site_url = stored.site_url || env_site_url() || server_address()

    %{
      site_url: site_url,
      secure_site_url: stored.secure_site_url || env_secure_site_url() || site_url
    }
  end

  @doc "The minutes a job may go without console output before it counts as hung."
  def default_job_timeout do
    stored().default_job_timeout || System.get_env("DEFAULT_JOB_TIMEOUT", "0")
  end

  @doc "Where published artifacts are stored, and how full the disk may get before they are purged."
  def artifact_config do
    stored = stored()

    %{
      artifacts_dir: stored.artifacts_dir || System.get_env("ARTIFACTS_DIR", "artifacts"),
      purge_start_disk_space:
        stored.purge_start_disk_space || gigabytes("EX_GOCD_PURGE_START_GB", 10.0),
      purge_upto_disk_space:
        stored.purge_upto_disk_space || gigabytes("EX_GOCD_PURGE_UPTO_GB", 20.0)
    }
  end

  @doc "The directory published artifacts are written to."
  def artifacts_dir, do: artifact_config().artifacts_dir

  @doc """
  Stores the settings `attrs` carries, leaving every other setting as it is.

  Refused settings come back as `{:error, changeset}` with the reason on the
  field that carries it.
  """
  def update(attrs) do
    stored()
    |> Setting.changeset(attrs)
    |> put_change(:id, @one_row)
    |> persist()
  end

  defp persist(changeset) do
    with {:ok, _written} <-
           Repo.insert(changeset,
             conflict_target: :id,
             on_conflict: {:replace, written_fields(changeset)}
           ) do
      {:ok, Repo.get!(Setting, @one_row)}
    end
  end

  # Only the settings this write carries: a column it does not name keeps the
  # value it has.
  defp written_fields(changeset), do: Map.keys(changeset.changes) ++ [:updated_at]

  defp stored, do: Repo.get(Setting, @one_row) || %Setting{}

  defp env_site_url, do: System.get_env("PHX_URL") || System.get_env("SITE_URL")

  defp env_secure_site_url,
    do: System.get_env("PHX_SECURE_URL") || System.get_env("SECURE_SITE_URL")

  defp server_address do
    port = Application.get_env(:ex_gocd, ExGoCDWeb.Endpoint)[:http][:port] || 4000
    "http://localhost:#{port}"
  end

  defp gigabytes(variable, default) do
    case System.get_env(variable) do
      nil ->
        default

      value ->
        case Float.parse(value) do
          {gigabytes, _rest} -> gigabytes
          :error -> default
        end
    end
  end
end
