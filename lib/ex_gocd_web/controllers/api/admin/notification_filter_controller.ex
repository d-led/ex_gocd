defmodule ExGoCDWeb.API.Admin.NotificationFilterController do
  use ExGoCDWeb, :controller
  alias ExGoCD.Notifications

  def index(conn, params) do
    case parse_counter(params["user_id"]) do
      {:ok, user_id} ->
        json(conn, %{data: Notifications.list_filters(user_id)})

      {:error, :not_a_counter} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "A user_id that is a whole number is required."})
    end
  end

  def create(conn, %{"notification_filter" => params}) do
    case Notifications.create_filter(params) do
      {:ok, filter} ->
        conn |> put_status(:created) |> json(%{data: filter})

      {:error, cs} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(cs)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{message: "A notification_filter is required."})
  end

  def delete(conn, %{"id" => id}) do
    case Notifications.delete_filter(id) do
      {:ok, _filter} ->
        json(conn, %{message: "Filter deleted"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Filter '#{id}' not found."})
    end
  end

  defp changeset_errors(cs),
    do:
      Ecto.Changeset.traverse_errors(cs, fn {m, o} ->
        Enum.reduce(o, m, fn {k, v}, a -> String.replace(a, "%{#{k}}", to_string(v)) end)
      end)
end
