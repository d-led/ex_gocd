defmodule ExGoCDWeb.API.ElasticAgentProfileController do
  use ExGoCDWeb, :controller

  alias ExGoCD.ElasticAgentProfiles

  def index(conn, _params) do
    profiles = ElasticAgentProfiles.list_profiles()
    render(conn, :index, profiles: profiles)
  end

  def show(conn, %{"id" => id}) do
    profile = ElasticAgentProfiles.get_profile!(id)
    render(conn, :show, profile: profile)
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
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "elastic_agent_profile" => params}) do
    profile = ElasticAgentProfiles.get_profile!(id)

    case ElasticAgentProfiles.update_profile(profile, params) do
      {:ok, profile} ->
        render(conn, :show, profile: profile)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    profile = ElasticAgentProfiles.get_profile!(id)
    {:ok, _profile} = ElasticAgentProfiles.delete_profile(profile)

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
