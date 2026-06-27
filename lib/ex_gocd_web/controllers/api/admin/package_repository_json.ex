defmodule ExGoCDWeb.API.Admin.PackageRepositoryJSON do
  def index(%{repos: repos}), do: %{data: Enum.map(repos, &data/1)}
  def show(%{repo: repo}), do: %{data: data(repo)}

  defp data(r),
    do: %{id: r.id, name: r.name, plugin_id: r.plugin_id, configuration: r.configuration}
end
