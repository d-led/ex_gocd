defmodule ExGoCD.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_gocd,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      # Built-in coverage, so `mix test --cover --export-coverage default` leaves
      # the coverdata `mix crap` reads, and a run under the floor fails. ExCoveralls
      # was here before; it reports but cannot fail, and cannot feed CRAP.
      test_coverage: [
        summary: [threshold: coverage_threshold()],
        # test/support is compiled only for tests and exercised by the tests it
        # exists for, so counting it measures the scaffolding. Mix filters by
        # module name rather than by path, so the names come from the directory.
        ignore_modules: test_support_modules()
      ],
      dialyzer: dialyzer()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ExGoCD.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        "test.setup": :test,
        cover: :test,
        complexity: :test,
        types: :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      # The PLT is expensive to build and cheap to keep; CI caches this directory
      # under a key made of the lockfile.
      plt_core_path: "priv/plts",
      plt_local_path: "priv/plts",
      # `:cover` — which the coverage export calls — lives in `tools`, so a PLT
      # without it reads those calls as functions that do not exist.
      plt_add_apps: [:mix, :ex_unit, :tools],
      # The types job is about the application: Mix tasks are operator tooling and
      # tests are exercised by running them.
      exclude_paths: ["lib/mix/tasks/**", "test/**"],
      # Stricter than the defaults: a function that can fail without saying so, or
      # a `case` with no way back, is a fault waiting for a caller.
      flags: [:error_handling, :extra_return, :missing_return]
    ]
  end

  # The floor is where the suite is, rounded down: raising it is a decision, not a
  # side effect of adding tests.
  defp coverage_threshold, do: 67

  defp test_support_modules do
    "test/support/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(&modules_defined_in/1)
  end

  defp modules_defined_in(path) do
    ~r/^defmodule ([\w.]+)/m
    |> Regex.scan(File.read!(path), capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&Module.concat([&1]))
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:sobelow, "~> 0.18", only: [:dev, :test], runtime: false},
      {:phoenix_live_dashboard, "~> 0.9"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:gen_smtp, "~> 1.2"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3.0"},
      {:bandit, "~> 1.5"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_process_propagator, "~> 0.3"},
      {:junit_formatter, "~> 3.4", only: [:test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:map_diff, "~> 1.3"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # CRAP: complexity squared by the coverage a function is missing. It reads
      # the coverdata `mix test --cover --export-coverage` writes.
      {:ex_crap, "~> 0.1.1", only: [:dev, :test], runtime: false},
      {:logger_backends, "~> 1.0"},
      {:yaml_elixir, "~> 2.11"},
      {:bodyguard, "~> 2.4"},
      {:ex_json_schema, "~> 0.10"},
      {:contex, "~> 0.5.0"},
      {:k8s, "~> 2.8"},
      {:open_api_spex, "~> 3.22"},
      {:libcluster, "~> 3.4"},
      {:horde, "~> 0.10"},
      {:argon2_elixir, "~> 4.1"},
      {:joken, "~> 2.6"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # Prepare the test database once. `mix test` deliberately does not create
      # or migrate anything: doing that on every run makes two concurrent runs
      # race on CREATE DATABASE.
      "test.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "test.coverage": ["cover"],
      # Coverage that CRAP can read afterwards. Plain `mix test --cover` prints a
      # report and leaves nothing behind.
      cover: ["test --cover --export-coverage default"],
      # Both application trees, because a web-layer function and a domain function
      # of the same score are not the same risk: the domain one is where the rules
      # live.
      complexity: [
        "cmd mix crap --path lib/ex_gocd --max-score 30",
        "cmd mix crap --path lib/ex_gocd_web --max-score 30"
      ],
      types: ["dialyzer"],
      quality: ["credo --strict", "dialyzer", "complexity"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind ex_gocd", "esbuild ex_gocd"],
      "assets.deploy": [
        "compile",
        "tailwind ex_gocd --minify",
        "esbuild ex_gocd --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
