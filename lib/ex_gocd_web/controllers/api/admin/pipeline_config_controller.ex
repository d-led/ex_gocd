defmodule ExGoCDWeb.API.Admin.PipelineConfigController do
  use ExGoCDWeb, :controller

  alias ExGoCD.{Pipelines, Repo}

  @doc "GET /api/admin/pipelines"
  def index(conn, _params) do
    pipelines = Pipelines.list_pipelines()
    json(conn, Enum.map(pipelines, &pipeline_to_json/1))
  end

  @doc "GET /api/admin/pipelines/:name"
  def show(conn, %{"name" => name}) do
    pipeline = Pipelines.get_pipeline_by_name(name)

    if is_nil(pipeline) do
      conn |> put_status(:not_found) |> json(%{message: "Pipeline '#{name}' not found."})
    else
      json(conn, pipeline_to_json(pipeline))
    end
  end

  @doc "POST /api/admin/pipelines"
  def create(conn, params) do
    attrs = %{
      name: params["name"],
      group: params["group"] || "defaultGroup",
      label_template: params["label_template"],
      lock_behavior: params["lock_behavior"] || "none",
      paused: Map.get(params, "paused", false),
      timer: params["timer"],
      timer_only_on_changes: Map.get(params, "timer_only_on_changes", false)
    }

    case Pipelines.create_pipeline(attrs) do
      {:ok, pipeline} ->
        conn |> put_status(:created) |> json(pipeline_to_json(pipeline))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: "Failed to create pipeline.", errors: format_errors(changeset)})
    end
  end

  @doc "PUT /api/admin/pipelines/:name"
  def update(conn, %{"name" => name} = params) do
    case Pipelines.get_pipeline_by_name(name) do
      nil ->
        conn |> put_status(:not_found) |> json(%{message: "Pipeline '#{name}' not found."})

      pipeline ->
        attrs =
          Map.take(
            params,
            ~w(group label_template lock_behavior paused timer timer_only_on_changes)
          )

        case Pipelines.update_pipeline(pipeline, attrs) do
          {:ok, updated} ->
            json(conn, pipeline_to_json(updated))

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{message: "Update failed.", errors: format_errors(changeset)})
        end
    end
  end

  @doc "DELETE /api/admin/pipelines/:name"
  def delete(conn, %{"name" => name}) do
    case Pipelines.get_pipeline_by_name(name) do
      nil ->
        conn |> put_status(:not_found) |> json(%{message: "Pipeline '#{name}' not found."})

      pipeline ->
        Pipelines.delete_pipeline(pipeline)
        json(conn, %{message: "Pipeline '#{name}' deleted."})
    end
  end

  defp pipeline_to_json(pipeline) do
    pipeline = Repo.preload(pipeline, stages: [jobs: :tasks])

    %{
      name: pipeline.name,
      group: pipeline.group,
      label_template: pipeline.label_template,
      lock_behavior: pipeline.lock_behavior,
      paused: pipeline.paused,
      timer: pipeline.timer,
      timer_only_on_changes: pipeline.timer_only_on_changes,
      stages:
        Enum.map(pipeline.stages || [], fn stage ->
          %{
            name: stage.name,
            approval_type: stage.approval_type || "success",
            fetch_materials: stage.fetch_materials,
            clean_working_dir: stage.clean_working_dir,
            never_cleanup_artifacts: stage.never_cleanup_artifacts,
            jobs:
              Enum.map(stage.jobs || [], fn job ->
                %{
                  name: job.name,
                  run_instance_count: job.run_instance_count,
                  timeout: job.timeout,
                  run_on_all_agents: job.run_on_all_agents,
                  resources: job.resources || [],
                  environment_variables: job.environment_variables || %{},
                  elastic_profile_id: job.elastic_profile_id,
                  tasks:
                    Enum.map(job.tasks || [], fn task ->
                      %{
                        type: task.type,
                        command: task.command,
                        args: task.args,
                        working_dir: task.working_dir,
                        run_if: task.run_if
                      }
                    end)
                }
              end)
          }
        end)
    }
  end
end
