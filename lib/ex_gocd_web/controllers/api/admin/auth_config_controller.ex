defmodule ExGoCDWeb.API.Admin.AuthConfigController do
  use ExGoCDWeb, :controller
  alias ExGoCD.AuthConfigs

  def index(conn, _params), do: render(conn, :index, configs: AuthConfigs.list_configs())
  def show(conn, %{"id" => id}), do: render(conn, :show, config: AuthConfigs.get_config!(id))

  def create(conn, %{"auth_config" => params}) do
    case AuthConfigs.create_config(params) do
      {:ok, config} -> conn |> put_status(:created) |> render(:show, config: config)
      {:error, cs} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(cs)})
    end
  end

  def update(conn, %{"id" => id, "auth_config" => params}) do
    case AuthConfigs.update_config(AuthConfigs.get_config!(id), params) do
      {:ok, config} -> render(conn, :show, config: config)
      {:error, cs} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(cs)})
    end
  end

  def delete(conn, %{"id" => id}) do
    AuthConfigs.get_config!(id) |> AuthConfigs.delete_config()
    conn |> put_status(:no_content) |> json(%{message: "Deleted"})
  end

  defp changeset_errors(cs), do: Ecto.Changeset.traverse_errors(cs, fn {m, o} -> Enum.reduce(o, m, fn {k, v}, a -> String.replace(a, "%{#{k}}", to_string(v)) end) end)
end
