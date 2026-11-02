defmodule ExGoCDWeb.API.Admin.SecretConfigController do
  use ExGoCDWeb, :controller
  alias ExGoCD.SecretConfigs

  def index(conn, _params), do: render(conn, :index, configs: SecretConfigs.list_configs())

  def show(conn, %{"id" => id}) do
    case SecretConfigs.get_config(id) do
      nil -> not_found(conn, "Secret config", id)
      config -> render(conn, :show, config: config)
    end
  end

  def create(conn, %{"secret_config" => params}) do
    case SecretConfigs.create_config(params) do
      {:ok, config} ->
        conn |> put_status(:created) |> render(:show, config: config)

      {:error, cs} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(cs)})
    end
  end

  def update(conn, %{"id" => id, "secret_config" => params}) do
    case SecretConfigs.get_config(id) do
      nil ->
        not_found(conn, "Secret config", id)

      config ->
        case SecretConfigs.update_config(config, params) do
          {:ok, updated} ->
            render(conn, :show, config: updated)

          {:error, cs} ->
            conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case SecretConfigs.get_config(id) do
      nil ->
        not_found(conn, "Secret config", id)

      config ->
        SecretConfigs.delete_config(config)
        conn |> put_status(:no_content) |> json(%{message: "Deleted"})
    end
  end
end
