defmodule ExGoCD.Mcp.Resources do
  @moduledoc """
  Documents this server publishes for a client to list and read by URI.

  A resource is something a person would *attach* — the configuration, the
  dashboard's state, the audit trail — and an answer that reads the same however
  it is asked for. Anything that takes arguments, or that writes, is a tool.

  Each one is its tool's structured answer, not a second implementation: the
  dashboard resource is what `gocd_dashboard` returns, the pipeline resource is
  what `gocd_describe_pipeline` returns. That is what keeps a resource from
  drifting into a slightly different truth from the tool beside it — and it
  means a resource is read as the caller, with the caller's permissions.
  """

  alias ExGoCD.Mcp.Tools

  @resources [
    %{
      "uri" => "gocd://dashboard",
      "name" => "dashboard",
      "title" => "Every pipeline's latest status",
      "description" =>
        "Each pipeline with its group, its latest run's counter and status, and whether it " <>
          "is paused — the same data `gocd_dashboard` returns.",
      "mimeType" => "application/json"
    },
    %{
      "uri" => "gocd://config.xml",
      "name" => "configuration",
      "title" => "The configuration as GoCD XML",
      "description" =>
        "This server's `cruise-config.xml`, as the config page and the admin API write it. " <>
          "Secret values stay encrypted.",
      "mimeType" => "application/xml"
    },
    %{
      "uri" => "gocd://audit/recent",
      "name" => "audit",
      "title" => "The last fifty audit entries",
      "description" => "Who did what, newest first — the same data `gocd_audit_log` returns.",
      "mimeType" => "application/json"
    }
  ]

  @templates [
    %{
      "uriTemplate" => "gocd://pipelines/{name}",
      "name" => "pipeline",
      "title" => "One pipeline's configuration",
      "description" =>
        "A pipeline's group, materials, stages, jobs, tasks, variables and parameters, as " <>
          "`gocd_describe_pipeline` returns them.",
      "mimeType" => "application/json"
    }
  ]

  @doc "The resources a client can read without arguments."
  @spec definitions() :: [map()]
  def definitions, do: @resources

  @doc "The resources addressed by filling in a template."
  @spec templates() :: [map()]
  def templates, do: @templates

  @doc """
  Reads one resource.

  Returns `{:ok, %{"uri" => uri, "mimeType" => mime, "text" => text}}` or an
  error sentence — a URI this server does not publish, or a tool that refused
  the read (a pipeline that does not exist, an entry the caller may not see).
  """
  @spec read(String.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def read(uri, ctx) when is_binary(uri) do
    case uri do
      "gocd://dashboard" ->
        json(uri, Tools.Server.call("gocd_dashboard", %{}, ctx))

      "gocd://audit/recent" ->
        json(uri, Tools.Server.call("gocd_audit_log", %{"limit" => 50}, ctx))

      "gocd://config.xml" ->
        xml(uri, Tools.Config.call("gocd_config_xml", %{}, ctx))

      "gocd://pipelines/" <> name ->
        pipeline(uri, URI.decode(name), ctx)

      _unpublished ->
        {:error, "No resource at `#{uri}`. `resources/list` says what this server publishes."}
    end
  end

  def read(uri, _ctx), do: {:error, "A resource URI must be a string, not #{inspect(uri)}."}

  defp pipeline(uri, "", _ctx), do: {:error, "A pipeline resource needs a name: `#{uri}`."}

  defp pipeline(uri, name, ctx) do
    json(uri, Tools.Pipelines.call("gocd_describe_pipeline", %{"name" => name}, ctx))
  end

  defp json(uri, {:ok, %{structured: structured}}) do
    {:ok,
     %{
       "uri" => uri,
       "mimeType" => "application/json",
       "text" => Jason.encode!(structured, pretty: true)
     }}
  end

  defp json(_uri, {:error, message}), do: {:error, message}

  defp xml(uri, {:ok, %{structured: %{"xml" => xml}}}) do
    {:ok, %{"uri" => uri, "mimeType" => "application/xml", "text" => xml}}
  end

  defp xml(_uri, {:error, message}), do: {:error, message}
end
