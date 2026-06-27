defmodule ExGoCDWeb.API.ClusterProfileController do
  use ExGoCDWeb, :controller

  alias ExGoCD.ClusterProfiles

  def index(conn, _params) do
    profiles = ClusterProfiles.list_profiles()
    render(conn, :index, profiles: profiles)
  end

  def show(conn, %{"id" => id}) do
    profile = ClusterProfiles.get_profile!(id)
    render(conn, :show, profile: profile)
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
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "cluster_profile" => params}) do
    profile = ClusterProfiles.get_profile!(id)

    case ClusterProfiles.update_profile(profile, params) do
      {:ok, profile} ->
        render(conn, :show, profile: profile)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    profile = ClusterProfiles.get_profile!(id)
    {:ok, _profile} = ClusterProfiles.delete_profile(profile)

    conn
    |> put_status(:no_content)
    |> json(%{message: "Profile deleted"})
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
