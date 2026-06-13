defmodule ExGoCD.Environments do
  @moduledoc """
  The Environments context - manages environments and pipeline associations.
  """
  import Ecto.Query, warn: false
  alias ExGoCD.Repo
  alias ExGoCD.Environments.Environment
  alias ExGoCD.Pipelines.Pipeline

  @doc """
  Lists all environments with preloaded pipelines.
  """
  def list_environments do
    Environment
    |> order_by(asc: :name)
    |> Repo.all()
    |> Repo.preload(:pipelines)
  end

  @doc """
  Gets a single environment.
  """
  def get_environment!(id) do
    Environment
    |> Repo.get!(id)
    |> Repo.preload(:pipelines)
  end

  @doc """
  Gets an environment by name.
  """
  def get_environment_by_name(name) when is_binary(name) do
    Environment
    |> Repo.get_by(name: name)
    |> Repo.preload(:pipelines)
  end
  def get_environment_by_name(_), do: nil

  @doc """
  Creates an environment.
  """
  def create_environment(attrs \\ %{}) do
    pipelines = get_pipelines_from_attrs(attrs)

    %Environment{}
    |> Environment.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:pipelines, pipelines || [])
    |> Repo.insert()
  end

  @doc """
  Updates an environment.
  """
  def update_environment(%Environment{} = env, attrs) do
    pipelines = get_pipelines_from_attrs(attrs)

    changeset = Environment.changeset(env, attrs)

    changeset =
      if pipelines do
        Ecto.Changeset.put_assoc(changeset, :pipelines, pipelines)
      else
        changeset
      end

    Repo.update(changeset)
  end

  @doc """
  Deletes an environment.
  """
  def delete_environment(%Environment{} = env) do
    Repo.delete(env)
  end

  @doc """
  Gets the environment associated with a pipeline name.
  """
  def get_pipeline_environment(pipeline_name) when is_binary(pipeline_name) do
    query =
      from(e in Environment,
        join: p in assoc(e, :pipelines),
        where: p.name == ^pipeline_name,
        preload: [:pipelines]
      )

    Repo.one(query)
  end
  def get_pipeline_environment(_), do: nil

  @doc """
  Adds a pipeline to an environment, removing it from any other environments.
  """
  def add_pipeline_to_environment(env_name, pipeline_name) when is_binary(env_name) and is_binary(pipeline_name) do
    with %Environment{} = env <- get_environment_by_name(env_name),
         %Pipeline{} = pipeline <- ExGoCD.Pipelines.get_pipeline_by_name(pipeline_name) do
      # Remove from any existing environments first
      remove_pipeline_from_any_environments(pipeline.id)

      # Insert join row
      Repo.insert_all("environment_pipelines", [%{environment_id: env.id, pipeline_id: pipeline.id}])
      {:ok, get_environment_by_name(env_name)}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Removes a pipeline from an environment.
  """
  def remove_pipeline_from_environment(env_name, pipeline_name) when is_binary(env_name) and is_binary(pipeline_name) do
    with %Environment{} = env <- get_environment_by_name(env_name),
         %Pipeline{} = pipeline <- ExGoCD.Pipelines.get_pipeline_by_name(pipeline_name) do
      query =
        from(ep in "environment_pipelines",
          where: ep.environment_id == ^env.id and ep.pipeline_id == ^pipeline.id
        )

      Repo.delete_all(query)
      {:ok, get_environment_by_name(env_name)}
    else
      nil -> {:error, :not_found}
    end
  end

  defp remove_pipeline_from_any_environments(pipeline_id) do
    query = from(ep in "environment_pipelines", where: ep.pipeline_id == ^pipeline_id)
    Repo.delete_all(query)
  end

  defp get_pipelines_from_attrs(attrs) do
    names =
      case Map.get(attrs, "pipelines") || Map.get(attrs, :pipelines) do
        nil -> nil
        list when is_list(list) ->
          Enum.map(list, fn
            p when is_binary(p) -> p
            p when is_map(p) -> Map.get(p, "name") || Map.get(p, :name)
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)
      end

    if names do
      Repo.all(from(p in Pipeline, where: p.name in ^names))
    else
      nil
    end
  end

  def change_environment(%Environment{} = env, attrs \\ %{}) do
    Environment.changeset(env, attrs)
  end
end
