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

  def approve_stage(conn, %{
        "pipeline_name" => pipeline_name,
        "counter" => counter,
        "stage_name" => stage_name
      }) do
    user = get_current_user(conn)

    if allowed?(user) do
      Pipelines.approve_stage(pipeline_name, String.to_integer(counter), stage_name)
      |> approval_outcome(stage_name)
      |> reply(conn)
    else
      forbidden(conn)
    end
  end

  defp approval_outcome({:ok, _stage_instance}, stage_name),
    do: {:ok, "Stage '#{stage_name}' approved successfully."}

  defp approval_outcome({:error, :stage_not_awaiting_approval}, stage_name),
    do: {:bad_request, "Stage '#{stage_name}' is not awaiting approval."}

  defp approval_outcome({:error, :stage_config_not_found}, _stage_name),
    do: {:not_found, "Stage config not found."}

  defp approval_outcome({:error, _reason}, _stage_name),
    do: {:unprocessable_entity, "Failed to approve stage."}

  defp reply({:ok, message}, conn) do
    conn
    |> put_status(:ok)
    |> render(:message, message: message)
  end

  defp reply({status, message}, conn) do
    conn
    |> put_status(status)
    |> json(%{error: message})
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
  def comment(conn, %{"pipeline_name" => name, "counter" => counter, "comment" => comment}) do
    user = get_current_user(conn)

    if allowed?(user) do
      number = String.to_integer(counter)

      case Pipelines.add_comment(name, number, comment) do
        {:ok, _instance} -> comment_saved(conn, user, name, number, comment)
        {:error, reason} -> comment_refused(conn, reason, name, number)
      end
    else
      forbidden(conn)
    end
  end

  defp comment_saved(conn, user, name, counter, comment) do
    ExGoCD.AuditLog.log(user.username, "pipeline_comment",
      resource_type: "pipeline",
      resource_name: name,
      details: %{counter: counter, comment: comment}
    )

    json(conn, %{message: "Comment added."})
  end

  defp comment_refused(conn, :pipeline_not_found, name, _counter) do
    conn |> put_status(:not_found) |> json(%{error: "Pipeline '#{name}' not found."})
  end

  defp comment_refused(conn, :instance_not_found, name, counter) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Pipeline instance #{name}/#{counter} not found."})
  end

  defp comment_refused(conn, reason, _name, _counter) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Failed to add comment: #{inspect(reason)}"})
  end

  defp allowed?(user) do
    ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :trigger_pipeline, user)
  end

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Forbidden"})
  end
end
