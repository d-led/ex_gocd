defmodule EnterpriseHierarchy.MixProject do
  use Mix.Project

  def project do
    [
      app: :enterprise_hierarchy,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {EnterpriseHierarchy.Application, []}
    ]
  end

  defp deps do
    [
      {:libcluster, "~> 3.4"},
      {:yamerl, "~> 0.10"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
    ]
  end
end
