defmodule ExGoCDWeb.API.PipelineOperationsController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Pipelines

  action_fallback ExGoCDWeb.FallbackController

  defp get_current_user(conn) do
    session = get_session(conn)
    ExGoCD.Accounts.get_current_user(session)
  end

  def pause(conn, %{"pipeline_name" => name} = params) do
    user = get_current_user(conn)
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        paused_by = user.username
        pause_cause = Map.get(params, "pause_cause", "")

        case Pipelines.pause_pipeline(name, paused_by, pause_cause) do
          {:ok, _pipeline} ->
            conn
            |> put_status(:ok)
            |> render(:message, message: "Pipeline '#{name}' paused successfully.")

          {:error, :pipeline_not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Pipeline '#{name}' not found."})

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to pause pipeline."})
        end

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})
    end
  end

  def unpause(conn, %{"pipeline_name" => name}) do
    user = get_current_user(conn)
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        case Pipelines.unpause_pipeline(name) do
          {:ok, _pipeline} ->
            conn
            |> put_status(:ok)
            |> render(:message, message: "Pipeline '#{name}' unpaused successfully.")

          {:error, :pipeline_not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Pipeline '#{name}' not found."})

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to unpause pipeline."})
        end

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})
    end
  end

  def approve_stage(conn, %{"pipeline_name" => pipeline_name, "counter" => counter_str, "stage_name" => stage_name}) do
    user = get_current_user(conn)
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        counter = String.to_integer(counter_str)
        case Pipelines.approve_stage(pipeline_name, counter, stage_name) do
          {:ok, _stage_instance} ->
            conn
            |> put_status(:ok)
            |> render(:message, message: "Stage '#{stage_name}' approved successfully.")

          {:error, :stage_not_awaiting_approval} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Stage '#{stage_name}' is not awaiting approval."})

          {:error, :stage_config_not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Stage config not found."})

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to approve stage."})
        end

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})
    end
  end

  def status(conn, %{"pipeline_name" => name}) do
    user = get_current_user(conn)
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        case Pipelines.get_pipeline_by_name(name) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Pipeline '#{name}' not found."})

          pipeline ->
            locked = Pipelines.pipeline_locked?(pipeline)
            conn
            |> put_status(:ok)
            |> put_view(json: ExGoCDWeb.API.PipelineOperationsJSON)
            |> render(:status, %{
              paused: pipeline.paused,
              paused_cause: pipeline.pause_cause || "",
              paused_by: pipeline.paused_by || "",
              locked: locked,
              schedulable: not pipeline.paused and not locked
            })
        end

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})
    end
  end

  def unlock(conn, %{"pipeline_name" => name}) do
    user = get_current_user(conn)
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        confirm_header = get_req_header(conn, "x-gocd-confirm")
        if List.first(confirm_header) in ["true", "confirm"] do
          case Pipelines.unlock_pipeline(name) do
            {:ok, _pipeline} ->
              conn
              |> put_status(:ok)
              |> put_view(json: ExGoCDWeb.API.PipelineOperationsJSON)
              |> render(:message, message: "Pipeline lock released for #{name}.")

            {:error, :pipeline_not_found} ->
              conn
              |> put_status(:not_found)
              |> json(%{error: "Pipeline '#{name}' not found."})

            {:error, _} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to unlock pipeline."})
          end
        else
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Missing required header 'X-GoCD-Confirm: true'"})
        end

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})
    end
  end

  def schedule(conn, %{"pipeline_name" => name} = params) do
    user = get_current_user(conn)
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        case Pipelines.trigger_pipeline(name, params) do
          {:ok, _instance} ->
            conn
            |> put_status(:accepted)
            |> put_view(json: ExGoCDWeb.API.PipelineOperationsJSON)
            |> render(:message, message: "Request to schedule pipeline #{name} accepted")

          {:error, :pipeline_not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Pipeline '#{name}' not found."})

          {:error, :pipeline_paused} ->
            conn
            |> put_status(:conflict)
            |> json(%{error: "Pipeline '#{name}' is paused."})

          {:error, :pipeline_locked} ->
            conn
            |> put_status(:conflict)
            |> json(%{error: "Pipeline '#{name}' is locked."})

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to schedule pipeline. Reason: #{inspect(reason)}"})
        end

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})
    end
  end

  @doc "POST /api/pipelines/:pipeline_name/:counter/comment"
  def comment(conn, %{"pipeline_name" => name, "counter" => counter_str, "comment" => comment}) do
    user = get_current_user(conn)
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user) do
      true ->
        counter = String.to_integer(counter_str)

        case Pipelines.add_comment(name, counter, comment) do
          {:ok, _instance} ->
            ExGoCD.AuditLog.log(user.username, "pipeline_comment",
              resource_type: "pipeline", resource_name: name,
              details: %{counter: counter, comment: comment})

            json(conn, %{message: "Comment added."})

          {:error, :pipeline_not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "Pipeline '#{name}' not found."})

          {:error, :instance_not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "Pipeline instance #{name}/#{counter} not found."})

          {:error, reason} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "Failed to add comment: #{inspect(reason)}"})
        end

      false ->
        conn |> put_status(:forbidden) |> json(%{error: "Forbidden"})
    end
  end
end
