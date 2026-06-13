defmodule ExGoCDWeb.API.Admin.EnvironmentController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Environments
  alias ExGoCD.Environments.Environment
  alias ExGoCD.Pipelines.Pipeline
  alias ExGoCD.Repo
  import Ecto.Query

  action_fallback ExGoCDWeb.FallbackController

  defp etag(%Environment{} = env) do
    :crypto.hash(:sha256, env.name <> DateTime.to_string(env.updated_at)) |> Base.encode16() |> String.downcase()
  end

  defp get_current_user(conn) do
    session = get_session(conn)
    ExGoCD.Accounts.get_current_user(session)
  end

  def index(conn, _params) do
    user = get_current_user(conn)
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :view_environments, user) do
      true ->
        environments = Environments.list_environments()
        conn
        |> put_resp_header("etag", ~s("#{index_etag(environments)}"))
        |> render(:index, environments: environments)
      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})
    end
  end

  defp index_etag(envs) do
    names = Enum.map_join(envs, ",", & &1.name)
    :crypto.hash(:sha256, names) |> Base.encode16() |> String.downcase()
  end

  def show(conn, %{"name" => name}) do
    user = get_current_user(conn)
    with true <- ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :view_environments, user),
         %Environment{} = env <- Environments.get_environment_by_name(name) do
      conn
      |> put_resp_header("etag", ~s("#{etag(env)}"))
      |> render(:show, environment: env)
    else
      false ->
        conn |> put_status(:forbidden) |> json(%{error: "Forbidden"})
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Environment not found"})
    end
  end

  def create(conn, params) do
    user = get_current_user(conn)
    case ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :manage_environments, user) do
      true ->
        case Environments.create_environment(params) do
          {:ok, env} ->
            env = Repo.preload(env, :pipelines)
            conn
            |> put_status(:created)
            |> put_resp_header("etag", ~s("#{etag(env)}"))
            |> render(:show, environment: env)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})
        end

      false ->
        conn |> put_status(:forbidden) |> json(%{error: "Forbidden"})
    end
  end

  def update(conn, %{"name" => name} = params) do
    user = get_current_user(conn)
    with true <- ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :manage_environments, user),
         %Environment{} = env <- Environments.get_environment_by_name(name) do

      etag = etag(env)
      if_match = get_req_header(conn, "if-match") |> List.first()
      normalized_if_match = if_match && String.replace(if_match, ~r/^"|"$/, "")

      if if_match && normalized_if_match != etag do
        conn
        |> put_status(:precondition_failed)
        |> json(%{message: "Precondition Failed (ETag mismatch)"})
      else
        update_attrs = apply_patch(env, params)
        case Environments.update_environment(env, update_attrs) do
          {:ok, updated} ->
            updated = Repo.preload(updated, :pipelines)
            conn
            |> put_resp_header("etag", ~s("#{etag(updated)}"))
            |> render(:show, environment: updated)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})
        end
      end
    else
      false ->
        conn |> put_status(:forbidden) |> json(%{error: "Forbidden"})
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Environment not found"})
    end
  end

  def delete(conn, %{"name" => name}) do
    user = get_current_user(conn)
    with true <- ExGoCD.Policies.permit?(ExGoCD.Policies.EnvironmentPolicy, :manage_environments, user),
         %Environment{} = env <- Environments.get_environment_by_name(name),
         {:ok, _} <- Environments.delete_environment(env) do
      conn
      |> put_status(:ok)
      |> json(%{message: "Environment '#{name}' was deleted successfully."})
    else
      false ->
        conn |> put_status(:forbidden) |> json(%{error: "Forbidden"})
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Environment not found"})
    end
  end

  defp apply_patch(env, params) do
    pipelines =
      case Map.get(params, "pipelines") do
        %{} = ops ->
          to_add = Map.get(ops, "add", [])
          to_remove = Map.get(ops, "remove", [])
          existing_names = Enum.map(env.pipelines, & &1.name)
          new_names = (existing_names ++ to_add) -- to_remove
          Repo.all(from(p in Pipeline, where: p.name in ^new_names))

        list when is_list(list) ->
          names =
            Enum.map(list, fn
              p when is_binary(p) -> p
              p when is_map(p) -> Map.get(p, "name") || Map.get(p, :name)
              _ -> nil
            end)
            |> Enum.reject(&is_nil/1)

          Repo.all(from(p in Pipeline, where: p.name in ^names))

        _ ->
          env.pipelines
      end

    env_vars =
      case Map.get(params, "environment_variables") do
        %{} = ops ->
          to_add = Map.get(ops, "add", [])
          to_remove = Map.get(ops, "remove", [])
          filtered = Enum.reject(env.environment_variables || [], fn var ->
            n = Map.get(var, "name") || Map.get(var, :name)
            n in to_remove
          end)
          filtered ++ to_add

        list when is_list(list) ->
          list

        _ ->
          env.environment_variables || []
      end

    %{
      "pipelines" => pipelines,
      "environment_variables" => env_vars
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
