# Copyright 2026 ex_gocd
# Release tasks helper for Ecto migrations in production releases.

defmodule ExGoCD.Release do
  @app :ex_gocd

  @doc """
  Runs pending migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Seeds the database with demo data (pipelines, users, etc.).
  Safe to run multiple times — skips already-seeded records.
  """
  def seed do
    load_app()
    seeds_path = Path.join(:code.priv_dir(@app), "repo/seeds.exs")

    if File.exists?(seeds_path) do
      for repo <- repos() do
        {:ok, _, _} =
          Ecto.Migrator.with_repo(repo, fn _repo ->
            Code.eval_file(seeds_path)
          end)
      end

      :ok
    else
      IO.warn("Seeds file not found at #{seeds_path}")
      :error
    end
  end

  @doc """
  Rolls back migrations for a repo to a specific version.
  """
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
