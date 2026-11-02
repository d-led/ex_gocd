defmodule ExGoCDWeb.API.Admin.ClusterProfileController do
  use ExGoCDWeb, :controller

  alias ExGoCD.ClusterProfiles

  def index(conn, _params) do
    profiles = ClusterProfiles.list_profiles()
    render(conn, :index, profiles: profiles)
  end

  def show(conn, %{"id" => id}) do
    case ClusterProfiles.get_profile(id) do
      nil -> not_found(conn, "Cluster profile", id)
      profile -> render(conn, :show, profile: profile)
    end
  end

  def create(conn, %{"cluster_profile" => params}) do
    case ClusterProfiles.create_profile(params) do
      {:ok, profile} ->
        conn
        |> put_status(:created)
        |> render(:show, profile: profile)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "cluster_profile" => params}) do
    case ClusterProfiles.get_profile(id) do
      nil ->
        not_found(conn, "Cluster profile", id)

      profile ->
        case ClusterProfiles.update_profile(profile, params) do
          {:ok, updated} ->
            render(conn, :show, profile: updated)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{errors: format_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case ClusterProfiles.get_profile(id) do
      nil ->
        not_found(conn, "Cluster profile", id)

      profile ->
        {:ok, _profile} = ClusterProfiles.delete_profile(profile)

        conn
        |> put_status(:no_content)
        |> json(%{message: "Profile deleted"})
    end
  end
end
