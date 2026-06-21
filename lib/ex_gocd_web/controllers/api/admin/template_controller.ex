defmodule ExGoCDWeb.API.Admin.TemplateController do
  use ExGoCDWeb, :controller

  alias ExGoCD.{Pipelines, Repo}
  alias ExGoCD.Pipelines.Template

  @doc "GET /api/admin/templates"
  def index(conn, _params) do
    templates = Pipelines.list_templates()
    json(conn, %{templates: Enum.map(templates, &template_json/1)})
  end

  @doc "GET /api/admin/templates/:name"
  def show(conn, %{"name" => name}) do
    case Pipelines.get_template_by_name(name) do
      nil -> conn |> put_status(:not_found) |> json(%{message: "Template '#{name}' not found."})
      template -> json(conn, template_json(template))
    end
  end

  @doc "POST /api/admin/templates"
  def create(conn, params) do
    attrs = %{
      name: params["name"],
      stages: params["stages"] || []
    }

    case Pipelines.create_template(attrs) do
      {:ok, template} -> conn |> put_status(:created) |> json(template_json(template))
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{message: "Failed to create template.", errors: format_errors(changeset)})
    end
  end

  @doc "PUT /api/admin/templates/:name"
  def update(conn, %{"name" => name} = params) do
    case Pipelines.get_template_by_name(name) do
      nil -> conn |> put_status(:not_found) |> json(%{message: "Template '#{name}' not found."})
      template ->
        attrs = Map.take(params, ~w(stages))
        case Pipelines.update_template(template, attrs) do
          {:ok, updated} -> json(conn, template_json(updated))
          {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{message: "Update failed.", errors: format_errors(changeset)})
        end
    end
  end

  @doc "DELETE /api/admin/templates/:name"
  def delete(conn, %{"name" => name}) do
    case Pipelines.get_template_by_name(name) do
      nil -> conn |> put_status(:not_found) |> json(%{message: "Template '#{name}' not found."})
      template ->
        Pipelines.delete_template(template)
        json(conn, %{message: "Template '#{name}' deleted."})
    end
  end

  defp template_json(template) do
    %{
      name: template.name,
      stages: template.stages || []
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
