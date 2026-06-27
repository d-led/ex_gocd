defmodule ExGoCDWeb.API.Admin.SecretConfigController do
  use ExGoCDWeb, :controller
  alias ExGoCD.SecretConfigs

  def index(conn, _params), do: render(conn, :index, configs: SecretConfigs.list_configs())
  def show(conn, %{"id" => id}), do: render(conn, :show, config: SecretConfigs.get_config!(id))

  def create(conn, %{"secret_config" => params}) do
    case SecretConfigs.create_config(params) do
      {:ok, config} -> conn |> put_status(:created) |> render(:show, config: config)
      {:error, cs} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(cs)})
    end
  end

  def update(conn, %{"id" => id, "secret_config" => params}) do
    case SecretConfigs.update_config(SecretConfigs.get_config!(id), params) do
      {:ok, config} -> render(conn, :show, config: config)
      {:error, cs} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(cs)})
    end
  end

  def delete(conn, %{"id" => id}) do
    SecretConfigs.get_config!(id) |> SecretConfigs.delete_config()
    conn |> put_status(:no_content) |> json(%{message: "Deleted"})
  end

  defp changeset_errors(cs), do: Ecto.Changeset.traverse_errors(cs, fn {m, o} -> Enum.reduce(o, m, fn {k, v}, a -> String.replace(a, "%{#{k}}", to_string(v)) end) end)
end
