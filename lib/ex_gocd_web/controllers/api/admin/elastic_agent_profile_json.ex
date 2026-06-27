defmodule ExGoCDWeb.API.Admin.ElasticAgentProfileJSON do
  def index(%{profiles: profiles}) do
    %{data: Enum.map(profiles, &data/1)}
  end

  def show(%{profile: profile}) do
    %{data: data(profile)}
  end

  defp data(profile) do
    %{
      id: profile.id,
      plugin_id: profile.plugin_id,
      cluster_profile_id: profile.cluster_profile_id,
      properties: profile.properties
    }
  end
end
