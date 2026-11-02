defmodule ExGoCDWeb.API.Admin.ArtifactStoreController do
  use ExGoCDWeb, :controller
  alias ExGoCD.ArtifactStores

  def index(conn, _params), do: render(conn, :index, stores: ArtifactStores.list_stores())

  def show(conn, %{"id" => id}) do
    case ArtifactStores.get_store(id) do
      nil -> not_found(conn, "Artifact store", id)
      store -> render(conn, :show, store: store)
    end
  end

  def create(conn, %{"artifact_store" => params}) do
    case ArtifactStores.create_store(params) do
      {:ok, store} ->
        conn |> put_status(:created) |> render(:show, store: store)

      {:error, cs} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(cs)})
    end
  end

  def update(conn, %{"id" => id, "artifact_store" => params}) do
    case ArtifactStores.get_store(id) do
      nil ->
        not_found(conn, "Artifact store", id)

      store ->
        case ArtifactStores.update_store(store, params) do
          {:ok, updated} ->
            render(conn, :show, store: updated)

          {:error, cs} ->
            conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case ArtifactStores.get_store(id) do
      nil ->
        not_found(conn, "Artifact store", id)

      store ->
        ArtifactStores.delete_store(store)
        conn |> put_status(:no_content) |> json(%{message: "Deleted"})
    end
  end

  defp changeset_errors(cs),
    do:
      Ecto.Changeset.traverse_errors(cs, fn {m, o} ->
        Enum.reduce(o, m, fn {k, v}, a -> String.replace(a, "%{#{k}}", to_string(v)) end)
      end)
end
