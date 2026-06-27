defmodule ExGoCDWeb.API.Admin.ArtifactStoreJSON do
  def index(%{stores: stores}), do: %{data: Enum.map(stores, &data/1)}
  def show(%{store: store}), do: %{data: data(store)}
  defp data(s), do: %{id: s.id, plugin_id: s.plugin_id, properties: s.properties}
end
