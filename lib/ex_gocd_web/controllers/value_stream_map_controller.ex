defmodule ExGoCDWeb.ValueStreamMapController do
  use ExGoCDWeb, :controller

  alias ExGoCD.Pipelines.ValueStreamMap

  def show(conn, %{"pipeline_name" => name, "pipeline_counter" => counter_raw}) do
    counter_str = String.replace_suffix(counter_raw, ".json", "")

    case Integer.parse(counter_str) do
      {counter, ""} ->
        case ValueStreamMap.get_pipeline_vsm(name, counter) do
          {:ok, vsm} ->
            json(conn, vsm)

          {:error, _reason} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Pipeline '#{name}' with counter '#{counter}' not found."})
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid pipeline counter."})
    end
  end

  def show_material(conn, %{"material_fingerprint" => fingerprint, "revision" => revision_raw}) do
    revision = String.replace_suffix(revision_raw, ".json", "")

    {:ok, vsm} = ValueStreamMap.get_material_vsm(fingerprint, revision)
    json(conn, vsm)
  end
end
