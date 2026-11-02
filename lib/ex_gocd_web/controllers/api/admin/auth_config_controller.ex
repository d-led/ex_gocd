defmodule ExGoCDWeb.API.Admin.AuthConfigController do
  use ExGoCDWeb, :controller
  alias ExGoCD.AuthConfigs

  def index(conn, _params), do: render(conn, :index, configs: AuthConfigs.list_configs())

  def show(conn, %{"id" => id}) do
    case AuthConfigs.get_config(id) do
      nil -> not_found(conn, "Auth config", id)
      config -> render(conn, :show, config: config)
    end
  end

  def create(conn, %{"auth_config" => params}) do
    case AuthConfigs.create_config(params) do
      {:ok, config} ->
        conn |> put_status(:created) |> render(:show, config: config)

      {:error, cs} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(cs)})
    end
  end

  def update(conn, %{"id" => id, "auth_config" => params}) do
    case AuthConfigs.get_config(id) do
      nil ->
        not_found(conn, "Auth config", id)

      config ->
        case AuthConfigs.update_config(config, params) do
          {:ok, updated} ->
            render(conn, :show, config: updated)

          {:error, cs} ->
            conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case AuthConfigs.get_config(id) do
      nil ->
        not_found(conn, "Auth config", id)

      config ->
        AuthConfigs.delete_config(config)
        conn |> put_status(:no_content) |> json(%{message: "Deleted"})
    end
  end
end
