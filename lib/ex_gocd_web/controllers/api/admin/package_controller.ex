defmodule ExGoCDWeb.API.Admin.PackageController do
  @moduledoc """
  CRUD API for packages within package repositories.
  GoCD parity: Packages API v2.
  """
  use ExGoCDWeb, :controller

  alias ExGoCD.Packages

  action_fallback ExGoCDWeb.FallbackController

  def index(conn, _params) do
    packages = Packages.list_packages()
    json(conn, %{packages: Enum.map(packages, &package_json/1)})
  end

  def show(conn, %{"id" => id}) do
    package = Packages.get_package(id)

    if package,
      do: json(conn, package_json(package)),
      else: conn |> put_status(:not_found) |> json(%{error: "Package not found"})
  end

  def create(conn, %{"package" => package_params} = params) do
    attrs =
      Map.merge(
        package_params,
        Map.take(params, ~w(name package_repository_id package_type configuration))
      )

    case Packages.create_package(attrs) do
      {:ok, package} ->
        conn |> put_status(:created) |> json(package_json(package))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def create(conn, params) do
    case Packages.create_package(params) do
      {:ok, package} ->
        conn |> put_status(:created) |> json(package_json(package))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Packages.get_package(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Package not found"})

      package ->
        attrs = Map.get(params, "package", params) |> Map.drop(["id"])

        case Packages.update_package(package, attrs) do
          {:ok, package} ->
            json(conn, package_json(package))

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{errors: changeset_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Packages.get_package(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Package not found"})

      package ->
        Packages.delete_package(package)
        json(conn, %{message: "Package deleted"})
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp package_json(p) do
    repo = Map.get(p, :package_repository)

    %{
      id: p.id,
      name: p.name,
      package_type: p.package_type,
      configuration: p.configuration,
      package_repository: if(repo, do: %{id: repo.id, name: repo.name}, else: nil)
    }
  end
end
