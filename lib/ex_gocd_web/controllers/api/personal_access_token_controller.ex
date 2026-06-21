defmodule ExGoCDWeb.API.PersonalAccessTokenController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Accounts

  action_fallback ExGoCDWeb.FallbackController

  defp get_current_user(conn) do
    session = get_session(conn)
    Accounts.get_current_user(session)
  end

  def index(conn, _params) do
    user = get_current_user(conn)

    if is_nil(user.id) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Unauthorized"})
    else
      tokens = Accounts.list_user_tokens(user.id)

      conn
      |> put_view(json: ExGoCDWeb.API.PersonalAccessTokenJSON)
      |> render(:index, tokens: tokens)
    end
  end

  def show(conn, %{"id" => id_str}) do
    user = get_current_user(conn)

    if is_nil(user.id) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Unauthorized"})
    else
      token_id = String.to_integer(id_str)

      case Accounts.get_user_token(user.id, token_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Token not found"})

        token ->
          conn
          |> put_view(json: ExGoCDWeb.API.PersonalAccessTokenJSON)
          |> render(:show, token: token)
      end
    end
  end

  def create(conn, params) do
    user = get_current_user(conn)

    if is_nil(user.id) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Unauthorized"})
    else
      case Map.get(params, "description") do
        desc when is_binary(desc) and desc != "" ->
          case Accounts.create_user_token(user.id, desc) do
            {:ok, token} ->
              conn
              |> put_status(:created)
              |> put_view(json: ExGoCDWeb.API.PersonalAccessTokenJSON)
              |> render(:create, token: token)

            {:error, _changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to create access token"})
          end

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Missing required parameter 'description'"})
      end
    end
  end

  def revoke(conn, %{"id" => id_str} = params) do
    user = get_current_user(conn)

    if is_nil(user.id) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Unauthorized"})
    else
      token_id = String.to_integer(id_str)

      case Accounts.get_user_token(user.id, token_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Token not found"})

        token ->
          cause = Map.get(params, "revoke_cause")

          case Accounts.revoke_token(token, user.username, cause) do
            {:ok, updated} ->
              conn
              |> put_status(:ok)
              |> put_view(json: ExGoCDWeb.API.PersonalAccessTokenJSON)
              |> render(:show, token: updated)

            {:error, _} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to revoke token"})
          end
      end
    end
  end
end
