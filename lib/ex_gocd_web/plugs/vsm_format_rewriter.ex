defmodule ExGoCDWeb.Plugs.VSMFormatRewriter do
  @moduledoc """
  Rewrites path_info for VSM API routes ending in .json to avoid router collisions.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case conn.path_info do
      ["pipelines", "value_stream_map", pipeline_name, pipeline_counter] ->
        if String.ends_with?(pipeline_counter, ".json") do
          %{conn | path_info: ["api_json", "pipelines", "value_stream_map", pipeline_name, pipeline_counter]}
        else
          conn
        end

      ["go", "pipelines", "value_stream_map", pipeline_name, pipeline_counter] ->
        if String.ends_with?(pipeline_counter, ".json") do
          %{conn | path_info: ["api_json", "go", "pipelines", "value_stream_map", pipeline_name, pipeline_counter]}
        else
          conn
        end

      ["materials", "value_stream_map", material_fingerprint, revision] ->
        if String.ends_with?(revision, ".json") do
          %{conn | path_info: ["api_json", "materials", "value_stream_map", material_fingerprint, revision]}
        else
          conn
        end

      ["go", "materials", "value_stream_map", material_fingerprint, revision] ->
        if String.ends_with?(revision, ".json") do
          %{conn | path_info: ["api_json", "go", "materials", "value_stream_map", material_fingerprint, revision]}
        else
          conn
        end

      _ ->
        conn
    end
  end
end
