defmodule ExGoCDWeb.API.Admin.NotificationFilterController do
  use ExGoCDWeb, :controller
  alias ExGoCD.Notifications

  def index(conn, %{"user_id" => user_id}) do
    json(conn, %{data: Notifications.list_filters(String.to_integer(user_id))})
  end

  def create(conn, %{"notification_filter" => params}) do
    case Notifications.create_filter(params) do
      {:ok, filter} -> conn |> put_status(:created) |> json(%{data: filter})
      {:error, cs} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(cs)})
    end
  end

  def delete(conn, %{"id" => id}) do
    {:ok, _} = Notifications.delete_filter(id)
    conn |> json(%{message: "Filter deleted"})
  end

  defp changeset_errors(cs), do: Ecto.Changeset.traverse_errors(cs, fn {m, o} -> Enum.reduce(o, m, fn {k, v}, a -> String.replace(a, "%{#{k}}", to_string(v)) end) end)
end
