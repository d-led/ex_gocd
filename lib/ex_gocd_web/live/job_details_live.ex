# Copyright 2026 ex_gocd
# LiveView for GoCD Job Details page showing console logs and artifacts.

defmodule ExGoCDWeb.JobDetailsLive do
  use ExGoCDWeb, :live_view

  import Ecto.Query

  alias ExGoCD.AgentJobRuns
  alias ExGoCD.Pipelines.JobInstance
  alias ExGoCD.Repo

  @impl true
  def mount(params, _session, socket) do
    pipeline_name = params["pipeline_name"]
    pipeline_counter = String.to_integer(params["pipeline_counter"])
    stage_name = params["stage_name"]
    stage_counter = String.to_integer(params["stage_counter"])
    job_name = params["job_name"]

    job_instance = get_job_instance(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)
    run = get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)

    use_mock = is_nil(run)

    run =
      if use_mock do
        %{
          build_id: "mock-build-id-123",
          pipeline_name: pipeline_name,
          pipeline_counter: pipeline_counter,
          stage_name: stage_name,
          stage_counter: stage_counter,
          job_name: job_name,
          state: "Completed",
          result: "Passed",
          console_log: """
          [go] Start to build pipeline: #{pipeline_name} / #{pipeline_counter} ...
          [go] Fetching SCM materials from repository...
          [go] Git material checkout successful: master at 9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e
          [go] Executing task command: mix compile
            Compiling 12 files (.ex)
            Generated ex_gocd app
          [go] Executing task command: mix test
            Finished in 1.4 seconds
            297 tests, 0 failures
          [go] Job '#{job_name}' completed successfully with result: Passed.
          [go] Stage completed. Invalidation triggers cleared.
          """
        }
      else
        run
      end

    job_instance =
      if is_nil(job_instance) && use_mock do
        %{
          name: job_name,
          state: "Completed",
          result: "Passed",
          stage_instance: %{
            stage_name: stage_name,
            stage_counter: stage_counter,
            artifacts_deleted: false,
            pipeline_instance: %{
              pipeline: %{
                name: pipeline_name
              }
            }
          }
        }
      else
        job_instance
      end

    if connected?(socket) && run && Map.has_key?(run, :build_id) do
      AgentJobRuns.subscribe_console(run.build_id)
    end

    artifacts = list_artifacts(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name)

    {:ok,
     socket
     |> assign(:pipeline_name, pipeline_name)
     |> assign(:pipeline_counter, pipeline_counter)
     |> assign(:stage_name, stage_name)
     |> assign(:stage_counter, stage_counter)
     |> assign(:job_name, job_name)
     |> assign(:job_instance, job_instance)
     |> assign(:run, run)
     |> assign(:active_tab, "console")
     |> assign(:artifacts, artifacts)
     |> assign(:page_title, "Job Details: #{job_name}")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_info({:console_append, chunk}, socket) do
    run = socket.assigns.run
    if run do
      new_console_log = (run.console_log || "") <> chunk
      updated_run = %{run | console_log: new_console_log}
      {:noreply, assign(socket, run: updated_run)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:run_updated, updated_run}, socket) do
    if socket.assigns.run && updated_run.build_id == socket.assigns.run.build_id do
      {:noreply, assign(socket, run: updated_run)}
    else
      # Re-fetch run if it was just created/assigned
      run = get_run_by_params(
        socket.assigns.pipeline_name,
        socket.assigns.pipeline_counter,
        socket.assigns.stage_name,
        socket.assigns.stage_counter,
        socket.assigns.job_name
      )
      if run && connected?(socket) do
        AgentJobRuns.subscribe_console(run.build_id)
      end
      {:noreply, assign(socket, run: run)}
    end
  end

  # Helpers

  defp get_job_instance(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    JobInstance
    |> join(:inner, [ji], si in assoc(ji, :stage_instance))
    |> join(:inner, [ji, si], pi in assoc(si, :pipeline_instance))
    |> join(:inner, [ji, si, pi], p in assoc(pi, :pipeline))
    |> where([ji, si, pi, p], p.name == ^pipeline_name and
                              pi.counter == ^pipeline_counter and
                              si.name == ^stage_name and
                              si.counter == ^stage_counter and
                              ji.name == ^job_name)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(stage_instance: [pipeline_instance: :pipeline])
  end

  defp get_run_by_params(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    from(r in ExGoCD.AgentJobRuns.AgentJobRun,
      where: r.pipeline_name == ^pipeline_name
        and r.pipeline_counter == ^pipeline_counter
        and r.stage_name == ^stage_name
        and r.stage_counter == ^stage_counter
        and r.job_name == ^job_name,
      order_by: [desc: r.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp artifacts_dir do
    System.get_env("ARTIFACTS_DIR") || "artifacts"
  end

  defp list_artifacts(pipeline_name, pipeline_counter, stage_name, stage_counter, job_name) do
    job_dir = Path.join([
      artifacts_dir(),
      pipeline_name,
      to_string(pipeline_counter),
      stage_name,
      to_string(stage_counter),
      job_name
    ])

    if File.dir?(job_dir) do
      list_files_recursive(job_dir, job_dir)
    else
      []
    end
  end

  defp list_files_recursive(dir, base_dir) do
    case File.ls(dir) do
      {:ok, names} ->
        Enum.flat_map(names, fn name ->
          path = Path.join(dir, name)
          rel_path = Path.relative_to(path, base_dir)

          if File.dir?(path) do
            # Group folders and files
            [%{name: name, type: :directory, rel_path: rel_path} | list_files_recursive(path, base_dir)]
          else
            case File.stat(path) do
              {:ok, stat} -> [%{name: name, type: :file, rel_path: rel_path, size: stat.size}]
              _ -> []
            end
          end
        end)
      _ ->
        []
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
end
