defmodule ExGoCD.Materials.Poller do
  use GenServer
  require Logger

  alias ExGoCD.Materials.GitClient
  alias ExGoCD.Pipelines
  alias ExGoCD.Pipelines.Material
  alias ExGoCD.Repo

  @moduledoc """
  A background GenServer that periodically polls Git materials for new revisions.
  When changes are detected, it creates a Modification and triggers the associated pipelines.
  """

  # API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def poll_now do
    GenServer.call(__MODULE__, :poll_now)
  end

  def poll_materials_by_url(url) when is_binary(url) do
    GenServer.call(__MODULE__, {:poll_materials_by_url, url})
  end

  # Callbacks
  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval) || Application.get_env(:ex_gocd, :poller_interval, 60_000)

    if is_integer(interval) do
      schedule_poll(interval)
    end

    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:poll, state) do
    do_poll()
    if is_integer(state.interval) do
      schedule_poll(state.interval)
    end
    {:noreply, state}
  end

  @impl true
  def handle_call(:poll_now, _from, state) do
    results = do_poll()
    {:reply, {:ok, results}, state}
  end

  @impl true
  def handle_call({:poll_materials_by_url, url}, _from, state) do
    results = do_poll_for_url(url)
    {:reply, {:ok, results}, state}
  end

  # Helper functions
  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp do_poll do
    Logger.debug("SCM Poller: starting check...")
    import Ecto.Query

    # Fetch all git materials
    materials =
      Repo.all(from m in Material, where: m.type == "git" and m.auto_update == true)
      |> Repo.preload(:pipelines)

    Enum.map(materials, fn material ->
      case GitClient.latest_revision(material.url, material.branch || "master") do
        {:ok, commit_info} ->
          check_and_trigger(material, commit_info)

        {:error, reason} ->
          Logger.error("SCM Poller: failed to check material #{material.url}: #{inspect(reason)}")
          {:error, material.id, reason}
      end
    end)
  end

  defp check_and_trigger(material, commit_info) do
    latest_mod = Pipelines.get_latest_modification(material.id)

    if is_nil(latest_mod) or latest_mod.revision != commit_info.revision do
      Logger.info("SCM Poller: new commit detected on #{material.url} [#{material.branch}]: #{commit_info.revision}")

      # Insert modification
      attrs = Map.put(commit_info, :material_id, material.id)
      case Pipelines.create_modification(attrs) do
        {:ok, _mod} ->
          triggered = Enum.map(material.pipelines, &trigger_associated_pipeline(&1, commit_info.revision))
          {:new_commit, material.id, commit_info.revision, triggered}

        {:error, changeset} ->
          Logger.error("SCM Poller: failed to save modification: #{inspect(changeset.errors)}")
          {:error, material.id, :save_failed}
      end
    else
      Logger.debug("SCM Poller: no changes detected on #{material.url} [#{material.branch}]")
      {:no_change, material.id}
    end
  end

  defp trigger_associated_pipeline(pipeline, revision) do
    case Pipelines.trigger_pipeline(pipeline.name) do
      {:ok, instance} ->
        Logger.info("SCM Poller: triggered pipeline #{pipeline.name} (run ##{instance.counter}) due to commit #{revision}")
        {pipeline.name, :triggered, instance.counter}

      {:error, reason} ->
        Logger.warning("SCM Poller: failed to trigger pipeline #{pipeline.name}: #{inspect(reason)}")
        {pipeline.name, :error, reason}
    end
  end

  defp do_poll_for_url(url) do
    Logger.debug("SCM Poller: starting check for url #{url}...")
    import Ecto.Query

    target_norm = normalize_git_url(url)

    # Fetch all git materials
    materials =
      Repo.all(from m in Material, where: m.type == "git" and m.auto_update == true)
      |> Repo.preload(:pipelines)
      |> Enum.filter(&(normalize_git_url(&1.url) == target_norm))

    Enum.map(materials, fn material ->
      case GitClient.latest_revision(material.url, material.branch || "master") do
        {:ok, commit_info} ->
          check_and_trigger(material, commit_info)

        {:error, reason} ->
          Logger.error("SCM Poller: failed to check material #{material.url}: #{inspect(reason)}")
          {:error, material.id, reason}
      end
    end)
  end

  @doc """
  Canonicalizes a git repository URL (resolves SSH/HTTPS/Git protocols and suffix/prefixes).
  """
  def normalize_git_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> String.replace(~r/^(https?|git|ssh|git\+ssh):\/\//, "")
    |> String.replace(~r/^git@/, "")
    |> String.replace(~r/:/, "/")
    |> String.replace(~r/\.git$/, "")
    |> String.downcase()
  end
  def normalize_git_url(_), do: ""
end
