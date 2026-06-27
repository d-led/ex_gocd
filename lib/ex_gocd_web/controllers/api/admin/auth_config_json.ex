defmodule ExGoCDWeb.API.Admin.AuthConfigJSON do
  def index(%{configs: configs}), do: %{data: Enum.map(configs, &data/1)}
  def show(%{config: config}), do: %{data: data(config)}
  defp data(c), do: %{id: c.id, plugin_id: c.plugin_id, properties: c.properties}
end
