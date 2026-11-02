defmodule ExGoCDWeb.API.Admin.ElasticAgentProfileController do
  use ExGoCDWeb, :controller

  alias ExGoCD.ElasticAgentProfiles

  def index(conn, _params) do
    profiles = ElasticAgentProfiles.list_profiles()
    render(conn, :index, profiles: profiles)
  end

  def show(conn, %{"id" => id}) do
    case ElasticAgentProfiles.get_profile(id) do
      nil -> not_found(conn, "Elastic agent profile", id)
      profile -> render(conn, :show, profile: profile)
    end
  end

  def create(conn, %{"elastic_agent_profile" => params}) do
    case ElasticAgentProfiles.create_profile(params) do
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

  def update(conn, %{"id" => id, "elastic_agent_profile" => params}) do
    case ElasticAgentProfiles.get_profile(id) do
      nil ->
        not_found(conn, "Elastic agent profile", id)

      profile ->
        case ElasticAgentProfiles.update_profile(profile, params) do
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
    case ElasticAgentProfiles.get_profile(id) do
      nil ->
        not_found(conn, "Elastic agent profile", id)

      profile ->
        {:ok, _profile} = ElasticAgentProfiles.delete_profile(profile)

        conn
        |> put_status(:no_content)
        |> json(%{message: "Profile deleted"})
    end
  end
end
