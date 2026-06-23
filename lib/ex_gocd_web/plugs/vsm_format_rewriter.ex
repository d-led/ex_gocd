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
        maybe_rewrite(
          conn,
          ["api_json", "pipelines", "value_stream_map", pipeline_name, pipeline_counter],
          pipeline_counter
        )

      ["go", "pipelines", "value_stream_map", pipeline_name, pipeline_counter] ->
        maybe_rewrite(
          conn,
          ["api_json", "go", "pipelines", "value_stream_map", pipeline_name, pipeline_counter],
          pipeline_counter
        )

      ["materials", "value_stream_map", material_fingerprint, revision] ->
        maybe_rewrite(
          conn,
          ["api_json", "materials", "value_stream_map", material_fingerprint, revision],
          revision
        )

      ["go", "materials", "value_stream_map", material_fingerprint, revision] ->
        maybe_rewrite(
          conn,
          ["api_json", "go", "materials", "value_stream_map", material_fingerprint, revision],
          revision
        )

      _ ->
        conn
    end
  end

  defp maybe_rewrite(conn, new_path_info, last_segment) do
    if String.ends_with?(last_segment, ".json") do
      %{conn | path_info: new_path_info}
    else
      conn
    end
  end
end
