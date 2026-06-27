defmodule ExGoCDWeb.API.Admin.SecretConfigJSON do
  def index(%{configs: configs}), do: %{data: Enum.map(configs, &data/1)}
  def show(%{config: config}), do: %{data: data(config)}

  defp data(c),
    do: %{
      id: c.id,
      name: c.name,
      plugin_id: c.plugin_id,
      configuration: c.configuration,
      description: c.description
    }
end
