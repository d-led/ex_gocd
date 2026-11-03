defmodule ExGoCDWeb.API.Admin.ElasticAgentProfileJSON do
  @moduledoc """
  An elastic agent profile in the shape api.go.cd documents.

  Two differences from what we store are the whole job of this module: the
  profile's `id` on the wire is its **name** (GoCD addresses a profile by the name
  its author gave it, not by a generated key), and `properties` is a list of
  `{key, value}` pairs where the row keeps a map.

  A value is sent as it is stored. The properties GoCD defines are strings, and so
  are ours, except for two this server seeds itself: `MinAgents` is a number and
  `ResourceImages` is an object. Sending those as JSON text would read back as a
  string and quietly lose the object, so they go out as they are.
  """
  @profiles_path "/api/elastic/profiles"
  @doc_url "https://api.gocd.org/current/#elastic-agent-profiles"

  def index(%{profiles: profiles}) do
    %{
      _links: %{
        self: %{href: @profiles_path},
        doc: %{href: @doc_url},
        find: %{href: "#{@profiles_path}/:profile_id"}
      },
      _embedded: %{profiles: Enum.map(profiles, &profile/1)}
    }
  end

  def show(%{profile: profile}), do: profile(profile)

  defp profile(profile) do
    %{
      _links: %{
        self: %{href: "#{@profiles_path}/#{profile.name}"},
        doc: %{href: @doc_url},
        find: %{href: "#{@profiles_path}/:profile_id"}
      },
      id: profile.name,
      cluster_profile_id: profile.cluster_profile_id,
      properties: properties(profile.properties)
    }
  end

  defp properties(nil), do: []

  defp properties(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> %{key: key, value: value} end)
  end
end
