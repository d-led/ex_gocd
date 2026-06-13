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
        paused_by = (user && user.username) || "anonymous"
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
end
