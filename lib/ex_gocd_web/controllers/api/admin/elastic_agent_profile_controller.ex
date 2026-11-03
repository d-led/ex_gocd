defmodule ExGoCDWeb.API.Admin.ElasticAgentProfileController do
  @moduledoc """
  Elastic agent profiles. GoCD addresses a profile by the name its author gave it,
  so `show`, `update` and `delete` accept either that name or the row's id, and a
  create may carry the name as `id` — see `attributes/1`.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.ElasticAgentProfiles

  def index(conn, _params) do
    profiles = ElasticAgentProfiles.list_profiles()
    render(conn, :index, profiles: profiles)
  end

  def show(conn, %{"id" => id}) do
    case ElasticAgentProfiles.find_profile(id) do
      nil -> not_found(conn, "Elastic agent profile", id)
      profile -> render(conn, :show, profile: profile)
    end
  end

  def create(conn, params) do
    case ElasticAgentProfiles.create_profile(attributes(params)) do
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

  def update(conn, %{"id" => id} = request) do
    case ElasticAgentProfiles.find_profile(id) do
      nil ->
        not_found(conn, "Elastic agent profile", id)

      profile ->
        case ElasticAgentProfiles.update_profile(profile, attributes(request)) do
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
    case ElasticAgentProfiles.find_profile(id) do
      nil ->
        not_found(conn, "Elastic agent profile", id)

      profile ->
        {:ok, _profile} = ElasticAgentProfiles.delete_profile(profile)

        conn
        |> put_status(:no_content)
        |> json(%{message: "Profile deleted"})
    end
  end

  # api.go.cd posts the profile at the top level, naming it `id` and giving
  # `properties` as a list of `{key, value}` pairs. Our older spelling wraps the
  # same thing in `elastic_agent_profile`. Both are read here, and the pair list
  # becomes the map the row keeps.
  defp attributes(%{"elastic_agent_profile" => inner}), do: attributes(inner)

  defp attributes(params) do
    params
    |> Map.take(~w(name id cluster_profile_id plugin_id properties))
    |> name_from_id()
    |> properties_to_map()
    |> Map.delete("id")
  end

  defp name_from_id(%{"name" => _name} = attrs), do: attrs
  defp name_from_id(%{"id" => id} = attrs), do: Map.put(attrs, "name", id)
  defp name_from_id(attrs), do: attrs

  defp properties_to_map(%{"properties" => pairs} = attrs) when is_list(pairs) do
    Map.put(
      attrs,
      "properties",
      Map.new(pairs, fn %{"key" => key, "value" => value} -> {key, value} end)
    )
  end

  defp properties_to_map(attrs), do: attrs
end
